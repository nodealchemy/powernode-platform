# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::DevLoopTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "dev-audit-test") }

  # C3: dev_next_task now surfaces relevant compound learnings on every claim, which
  # calls through to Ai::Memory::EmbeddingService. Force the keyword-fallback path
  # deterministically (rather than depending on Redis / the test-env mock embedding)
  # so unrelated tests in this file aren't coupled to embedding infrastructure.
  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
  end

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("dev_loop")
      expect(defn[:parameters][:action][:required]).to be true
    end

    it "exposes the bridge actions" do
      expect(described_class.action_definitions.keys)
        .to contain_exactly("dev_next_task", "dev_complete_task", "delegate_ralph_task", "dev_list_tasks",
                            "dev_update_task")
    end
  end

  describe ".permitted?" do
    it "requires ai.agents.update permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.update")
    end
  end

  describe "dev_next_task" do
    it "claims the highest-priority pending task and starts the loop" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "low", priority: 1)
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "high", priority: 20)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name })

      expect(result[:success]).to be true
      expect(result[:task][:task_key]).to eq("high")
      task = ralph_loop.ralph_tasks.find_by(task_key: "high")
      expect(task.status).to eq("in_progress")
      expect(task.execution_attempts).to eq(1)
      expect(task.metadata["claimed_by"]).to eq("user:#{user.id}")
      expect(ralph_loop.reload.status).to eq("running")
    end

    it "re-injects prior context every iteration (G12): learnings, open decisions, base files" do
      campaign = create(:ai_campaign, account: account)
      ralph_loop.update!(campaign: campaign,
                         configuration: { "base_context_files" => ["CLAUDE.md", "docs/contributing/conventions"] })
      ralph_loop.add_learning("Prefer the generic seam over a direct extension ref")
      campaign.record_decision!(decision_type: "build", title: "Unify the approval flows")
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "ctx", priority: 5)

      ctx = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })[:context]

      expect(ctx[:recent_learnings].last["text"]).to match(/generic seam/)
      expect(ctx[:open_decisions].size).to eq(1)
      expect(ctx[:base_context_files]).to eq(["CLAUDE.md", "docs/contributing/conventions"])
    end

    it "omits open_decisions when the loop has no campaign" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "ctx", priority: 5)
      ctx = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })[:context]
      expect(ctx).to have_key(:recent_learnings)
      expect(ctx).not_to have_key(:open_decisions)
    end

    # C3: unlike recent_learnings (this loop's own raw captures), relevant_learnings
    # surfaces the top-k most RELEVANT compound learnings across the whole corpus for
    # the specific task being claimed — closing the gap where a primary (Claude Code)
    # executor's dev_complete_task learnings were never handed back on the next claim.
    describe "surfaces relevant compound learnings for the claimed task (C3)" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_injection, account).and_return(true)
      end

      it "injects the top-k most relevant compound learnings, reusing build_compound_context's ranking" do
        learning = create(:ai_compound_learning, account: account, status: "active",
                          category: "best_practice", title: "Cache reporting queries",
                          content: "Always cache repeated reporting queries", importance_score: 0.8)
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "cache-task", priority: 5,
               description: "Optimize caching queries in the reporting service",
               acceptance_criteria: "Reporting queries should hit the cache")

        ctx = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })[:context]

        expect(ctx[:relevant_learnings]).to be_present
        entry = ctx[:relevant_learnings].find { |l| l[:id] == learning.id }
        expect(entry).to include(category: "best_practice", title: "Cache reporting queries")
      end

      it "caps relevant_learnings at RELEVANT_LEARNINGS_LIMIT" do
        6.times do |i|
          create(:ai_compound_learning, account: account, status: "active",
                 content: "Cache reporting queries pattern #{i}", importance_score: 0.5)
        end
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "cache-task", priority: 5,
               description: "Optimize caching queries", acceptance_criteria: "n/a")

        ctx = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })[:context]

        expect(ctx[:relevant_learnings].size).to eq(described_class::RELEVANT_LEARNINGS_LIMIT)
      end

      it "excludes retired learnings" do
        retired = create(:ai_compound_learning, account: account, status: "retired",
                         content: "Cache reporting queries retired pattern", importance_score: 0.9)
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "cache-task", priority: 5,
               description: "Optimize caching queries", acceptance_criteria: "n/a")

        ctx = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })[:context]

        ids = (ctx[:relevant_learnings] || []).map { |l| l[:id] }
        expect(ids).not_to include(retired.id)
      end

      it "bumps injection_count/last_injected_at on surfaced learnings" do
        learning = create(:ai_compound_learning, account: account, status: "active",
                          content: "Cache reporting queries", importance_score: 0.8, injection_count: 0)
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "cache-task", priority: 5,
               description: "Optimize caching queries", acceptance_criteria: "n/a")

        tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(learning.reload.injection_count).to eq(1)
        expect(learning.last_injected_at).to be_present
      end

      it "omits relevant_learnings entirely when nothing matches (keeps payload lean)" do
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "no-match", priority: 5,
               description: "Completely unrelated widget frobnication", acceptance_criteria: "n/a")

        ctx = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })[:context]

        expect(ctx).not_to have_key(:relevant_learnings)
      end
    end

    # G12 (IMP-c46281b749ed): a non-Claude executor on the platform path can't read
    # the base structural files itself, so re-inject their CONTENTS (size-bounded)
    # — not just the paths — each iteration to mitigate goal drift.
    describe "re-injects base file CONTENTS (G12)" do
      let(:ctx_root) { Rails.root.parent } # repo root — CLAUDE.md / docs live above server/
      let(:rel_dir)  { "server/tmp/base_ctx_spec#{ENV.fetch('TEST_ENV_NUMBER', '')}" }
      let(:abs_dir)  { ctx_root.join(rel_dir) }

      before do
        FileUtils.mkdir_p(abs_dir)
        File.write(abs_dir.join("small.md"), "BASE RULE ALPHA: prefer the generic seam")
        File.write(abs_dir.join("big.md"), "X" * 40_000)
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "ctx", priority: 5)
      end

      after { FileUtils.rm_rf(abs_dir) }

      def contents_for(files)
        ralph_loop.update!(configuration: { "base_context_files" => files })
        tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })[:context][:base_context_contents]
      end

      it "includes an existing base file's contents (not just its path)" do
        entry = contents_for(["#{rel_dir}/small.md"]).find { |c| c[:path] == "#{rel_dir}/small.md" }
        expect(entry).to be_present
        expect(entry[:contents]).to include("BASE RULE ALPHA")
        expect(entry[:truncated]).to be false
        expect(entry[:bytes]).to eq(entry[:contents].bytesize)
      end

      it "truncates an oversized base file (head + truncated marker, capped bytes)" do
        entry = contents_for(["#{rel_dir}/big.md"]).find { |c| c[:path] == "#{rel_dir}/big.md" }
        expect(entry[:truncated]).to be true
        expect(entry[:bytes]).to be <= described_class::BASE_CONTEXT_PER_FILE_LIMIT
        expect(entry[:contents].bytesize).to eq(entry[:bytes])
      end

      it "skips a missing base file without raising" do
        contents = contents_for(["#{rel_dir}/missing.md", "#{rel_dir}/small.md"])
        expect(contents.map { |c| c[:path] }).to contain_exactly("#{rel_dir}/small.md")
      end

      it "skips a directory path (non-file) without raising" do
        contents = contents_for([rel_dir, "#{rel_dir}/small.md"])
        expect(contents.map { |c| c[:path] }).to contain_exactly("#{rel_dir}/small.md")
      end

      it "never reads paths that escape the repo root" do
        contents = contents_for(["../../../../../etc/hostname", "#{rel_dir}/small.md"])
        expect(contents.map { |c| c[:path] }).to contain_exactly("#{rel_dir}/small.md")
      end

      it "still injects the base_context_files paths alongside the contents" do
        ralph_loop.update!(configuration: { "base_context_files" => ["#{rel_dir}/small.md"] })
        ctx = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })[:context]
        expect(ctx[:base_context_files]).to eq(["#{rel_dir}/small.md"])
        expect(ctx[:base_context_contents]).to be_present
      end
    end

    it "is idempotent — re-claiming returns the same in-progress task" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "only")

      first = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
      second = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(first[:reclaimed]).to be false
      expect(second[:reclaimed]).to be true
      expect(second[:task][:task_key]).to eq("only")
      expect(ralph_loop.ralph_tasks.in_progress.count).to eq(1)
    end

    describe "per-holder concurrent claims" do
      it "characterization: default config (no max_concurrent_claims) matches today's single-claim behavior" do
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "low", priority: 1)
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "high", priority: 20)

        first = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-a" })
        second = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-b" })

        expect(first[:task][:task_key]).to eq("high")
        # No opt-in (cap=1): lane-b is refused, not handed the colliding/other task,
        # and it never reclaims lane-a's task either.
        expect(second[:task]).to be_nil
        expect(second[:halted]).to be true
        expect(second[:reason]).to eq("max_concurrent_claims_reached")
        expect(ralph_loop.ralph_tasks.in_progress.count).to eq(1)
      end

      it "lets two holders claim two file-disjoint pending tasks when max_concurrent_claims=2" do
        ralph_loop.update!(configuration: { "max_concurrent_claims" => 2 })
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "t1", priority: 20,
                               metadata: { "files" => ["a.rb"] })
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "t2", priority: 10,
                               metadata: { "files" => ["b.rb"] })

        first = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-a" })
        second = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-b" })

        expect(first[:task][:task_key]).to eq("t1")
        expect(second[:task][:task_key]).to eq("t2")
        expect(ralph_loop.ralph_tasks.in_progress.count).to eq(2)
      end

      it "refuses a second holder a file-overlapping task instead of handing it out" do
        ralph_loop.update!(configuration: { "max_concurrent_claims" => 2 })
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "t1", priority: 20,
                               metadata: { "files" => ["a.rb"] })
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "t2", priority: 10,
                               metadata: { "files" => ["a.rb"] })

        tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-a" })
        second = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-b" })

        expect(second[:task]).to be_nil
        expect(second[:no_eligible_task]).to be true
        expect(second[:reason]).to eq("file_collision")
        expect(ralph_loop.ralph_tasks.in_progress.count).to eq(1)
      end

      it "never concurrently claims a task with missing/empty files (unknown blast radius)" do
        ralph_loop.update!(configuration: { "max_concurrent_claims" => 2 })
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "t1", priority: 20,
                               metadata: { "files" => ["a.rb"] })
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "t2", priority: 10)

        tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-a" })
        second = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-b" })

        expect(second[:task]).to be_nil
        expect(second[:no_eligible_task]).to be true
      end

      it "treats two tasks under the same extensions/private submodule as colliding" do
        ralph_loop.update!(configuration: { "max_concurrent_claims" => 2 })
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "t1", priority: 20,
                               metadata: { "files" => ["extensions/private/somepriv/foo.rb"] })
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "t2", priority: 10,
                               metadata: { "files" => ["extensions/private/somepriv/bar.rb"] })

        tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-a" })
        second = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "cc-lane-b" })

        expect(second[:task]).to be_nil
        expect(second[:no_eligible_task]).to be true
      end

      it "re-claims a pre-fix in-progress task (no claimed_holder) for any holder of the same user" do
        task = create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop, task_key: "legacy",
                                       metadata: { "claimed_by" => "user:#{user.id}", "claimed_at" => Time.current.iso8601 })

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id, holder: "any-lane" })

        expect(result[:reclaimed]).to be true
        expect(result[:task][:task_key]).to eq("legacy")
        expect(task.reload.status).to eq("in_progress")
      end
    end

    it "never hands out human-decision tasks" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "decision",
                             execution_type: "human", priority: 50)
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "code-fix", priority: 1)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:task][:task_key]).to eq("code-fix")
    end

    it "skips tasks whose dependencies are unsatisfied" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "first", priority: 1)
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "second",
                             priority: 20, dependencies: ["first"])

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:task][:task_key]).to eq("first")
    end

    it "reports an empty queue when nothing is claimable" do
      create(:ai_ralph_task, :passed, ralph_loop: ralph_loop)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:success]).to be true
      expect(result[:queue_empty]).to be true
      expect(result[:task]).to be_nil
    end

    it "includes loop guardrails and spec path from configuration" do
      ralph_loop.update!(configuration: {
        "loop_spec_path" => ".claude/loops/dev-audit/PROMPT.md",
        "guardrails" => ["specific: one task per iteration"]
      })
      create(:ai_ralph_task, ralph_loop: ralph_loop)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:loop][:loop_spec_path]).to eq(".claude/loops/dev-audit/PROMPT.md")
      expect(result[:loop][:guardrails]).to eq(
        Ai::DevLoop::LoopGuardrails.refresh(["specific: one task per iteration"])
      )
      expect(result[:loop][:guardrails]).to include("specific: one task per iteration")
    end

    it "serves the CURRENT shared guardrails, not a stale persisted snapshot" do
      # Simulate a persisted snapshot from before a HEAD/TAIL tuning: only the
      # loop-specific middle line was persisted (no shared lines at all).
      ralph_loop.update!(configuration: { "guardrails" => ["specific: stale-only middle line"] })
      create(:ai_ralph_task, ralph_loop: ralph_loop)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      served = result[:loop][:guardrails]
      expect(served.first(Ai::DevLoop::LoopGuardrails::HEAD.size)).to eq(Ai::DevLoop::LoopGuardrails::HEAD)
      expect(served.last(Ai::DevLoop::LoopGuardrails::TAIL.size)).to eq(Ai::DevLoop::LoopGuardrails::TAIL)
      expect(served).to include("specific: stale-only middle line")
    end

    it "serves plain compose when persisted guardrails are missing (no crash)" do
      ralph_loop.update!(configuration: {})
      create(:ai_ralph_task, ralph_loop: ralph_loop)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:loop][:guardrails]).to eq(Ai::DevLoop::LoopGuardrails.compose)
    end

    context "halt conditions" do
      before { create(:ai_ralph_task, ralph_loop: ralph_loop) }

      it "refuses to hand out tasks during an emergency halt" do
        account.suspend_ai!

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("emergency_halt")
        expect(result[:task]).to be_nil
      end

      it "refuses when the loop schedule is paused" do
        ralph_loop.update!(schedule_paused: true)

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("schedule_paused")
      end

      it "refuses when the loop is in a paused state" do
        ralph_loop.update!(status: "running")
        ralph_loop.pause!

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("loop_paused")
      end

      it "refuses when max iterations are reached" do
        ralph_loop.update!(max_iterations: 2, current_iteration: 2)

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("max_iterations_reached")
      end
    end

    # G5: goal-driven terminator + runtime-aware hard caps (these get their own
    # setup — the "halt conditions" before-block seeds a pending task, which would
    # defeat goal_met).
    context "G5 stop conditions" do
      it "ends the loop when the configured completion goal is met (goal_met terminator)" do
        ralph_loop.update!(status: "running", started_at: Time.current,
                           configuration: { "completion" => { "all_tasks_terminal" => true } })
        create(:ai_ralph_task, :passed, ralph_loop: ralph_loop, task_key: "done")

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("goal_met")
        expect(result[:task]).to be_nil
        expect(ralph_loop.reload.status).to eq("completed")
      end

      it "halts on a wall-clock timeout" do
        ralph_loop.update!(status: "running", started_at: 2.hours.ago,
                           configuration: { "max_wall_clock_seconds" => 60 })
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "slow")

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("wall_clock_exceeded")
        expect(result[:task]).to be_nil
      end

      it "halts a metered (platform) loop over its token cap" do
        metered = create(:ai_ralph_loop, account: account, driver_kind: "platform_agent",
                         status: "running", started_at: Time.current,
                         configuration: { "max_tokens" => 1000 })
        create(:ai_ralph_iteration, ralph_loop: metered, iteration_number: 1,
                                    tokens_input: 800, tokens_output: 800)
        create(:ai_ralph_task, ralph_loop: metered, task_key: "x")

        result = tool.execute(params: { action: "dev_next_task", loop_id: metered.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("token_cap_exceeded")
      end

      it "leaves a flat-rate claude_code loop UNCAPPED over the same nominal spend" do
        flat = create(:ai_ralph_loop, account: account, driver_kind: "claude_code",
                      status: "running", started_at: Time.current,
                      configuration: { "max_tokens" => 1000 })
        create(:ai_ralph_iteration, ralph_loop: flat, iteration_number: 1,
                                    tokens_input: 800, tokens_output: 800)
        create(:ai_ralph_task, ralph_loop: flat, task_key: "y")

        result = tool.execute(params: { action: "dev_next_task", loop_id: flat.id })

        expect(result[:halted]).to be_falsey
        expect(result[:task][:task_key]).to eq("y")
      end
    end

    it "returns an error for an unknown loop" do
      result = tool.execute(params: { action: "dev_next_task", loop_id: "nope" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/)
    end
  end

  describe "dev_list_tasks" do
    it "returns only tasks of the requested status with full task_details" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "pend-1")
      create(:ai_ralph_task, :passed, ralph_loop: ralph_loop, task_key: "pass-1")
      create(:ai_ralph_task, :blocked, ralph_loop: ralph_loop, task_key: "blk-1")
      create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop, task_key: "ip-1")

      result = tool.execute(params: { action: "dev_list_tasks", loop_id: ralph_loop.id, status: "blocked" })

      expect(result[:success]).to be true
      expect(result[:status]).to eq("blocked")
      expect(result[:count]).to eq(1)
      expect(result[:total_matching]).to eq(1)
      expect(result[:tasks].map { |t| t[:task_key] }).to contain_exactly("blk-1")
      # same shape as dev_next_task's task object (task_details)
      task = result[:tasks].first
      expect(task[:status]).to eq("blocked")
      expect(task).to include(:description, :acceptance_criteria, :metadata, :created_at)
    end

    it "returns all tasks when no status filter is given (respecting limit)" do
      create_list(:ai_ralph_task, 3, ralph_loop: ralph_loop)

      result = tool.execute(params: { action: "dev_list_tasks", loop_id: ralph_loop.id })

      expect(result[:success]).to be true
      expect(result[:status]).to be_nil
      expect(result[:count]).to eq(3)
      expect(result[:total_matching]).to eq(3)
      expect(result[:queue]).to include(:pending, :in_progress, :passed, :failed, :blocked)
    end

    it "rejects an invalid status" do
      result = tool.execute(params: { action: "dev_list_tasks", loop_id: ralph_loop.id, status: "frozen" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Invalid status/)
    end

    it "returns an error for an unknown loop" do
      result = tool.execute(params: { action: "dev_list_tasks", loop_id: "nope" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/)
    end

    it "clamps the limit into the 1..200 range" do
      create_list(:ai_ralph_task, 3, ralph_loop: ralph_loop)

      lowered = tool.execute(params: { action: "dev_list_tasks", loop_id: ralph_loop.id, limit: 0 })
      expect(lowered[:count]).to eq(1)            # clamped up to 1
      expect(lowered[:total_matching]).to eq(3)

      raised = tool.execute(params: { action: "dev_list_tasks", loop_id: ralph_loop.id, limit: 9999 })
      expect(raised[:count]).to eq(3)             # clamped down to 200; only 3 exist
    end

    it "flags a stale claim and counts it in the queue snapshot" do
      stub_const("Ai::RalphTask::STALE_CLAIM_THRESHOLD", 5.minutes)
      create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop, task_key: "stale-1",
             metadata: { "claimed_at" => 10.minutes.ago.iso8601 })
      create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop, task_key: "fresh-1",
             metadata: { "claimed_at" => 1.minute.ago.iso8601 })

      result = tool.execute(params: { action: "dev_list_tasks", loop_id: ralph_loop.id, status: "in_progress" })

      stale_task = result[:tasks].find { |t| t[:task_key] == "stale-1" }
      fresh_task = result[:tasks].find { |t| t[:task_key] == "fresh-1" }
      expect(stale_task[:stale]).to be true
      expect(fresh_task[:stale]).to be false
      expect(result[:queue][:stale_tasks]).to eq(1)
    end
  end

  describe "dev_complete_task" do
    let!(:task) do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "F9-99")
    end

    before do
      ralph_loop.update!(status: "running", started_at: Time.current)
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
    end

    it "records a passed outcome with iteration evidence and learning" do
      result = tool.execute(params: {
        action: "dev_complete_task",
        loop_id: ralph_loop.id,
        task_key: "F9-99",
        outcome: "passed",
        summary: "Fixed the gate enum and added a regression spec",
        check_results: { "rspec" => "2 examples, 0 failures" },
        files_changed: ["server/app/models/ai/mission_approval.rb"],
        git_branch: "dev-loop/dev-audit",
        commit_sha: "abc1234",
        learning: "Template-defined gates must be in the parent GATES enum"
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("passed")

      iteration = ralph_loop.ralph_iterations.last
      expect(iteration.status).to eq("completed")
      expect(iteration.checks_passed).to be true
      expect(iteration.git_branch).to eq("dev-loop/dev-audit")
      expect(iteration.git_commit_sha).to eq("abc1234")
      expect(iteration.check_results["rspec"]).to eq("2 examples, 0 failures")
      expect(iteration.check_results["files_changed"]).to include("server/app/models/ai/mission_approval.rb")
      expect(iteration.learning_extracted).to match(/GATES enum/)
      expect(ralph_loop.reload.learnings.last["text"]).to match(/GATES enum/)
      expect(result[:queue][:passed]).to eq(1)
    end

    it "transitions the loop to completed when the last task passes and none remain (IMP-af21b11d476c)" do
      # F9-99 (the only task) is the one being completed here — passing it should
      # be the LAST outstanding task, so all_tasks_completed? goes true and the
      # loop itself (not just the task) should flip to completed.
      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "F9-99",
        outcome: "passed", summary: "done"
      })

      expect(result[:success]).to be true
      expect(result[:all_tasks_completed]).to be true
      expect(ralph_loop.reload.status).to eq("completed")
      expect(ralph_loop.completed_at).to be_present
    end

    it "does NOT force-complete a campaign-tied loop even when its current tasks are all terminal (regression guard)" do
      # A campaign's loop is open-ended -- more increments are expected on it
      # later. Force-completing it here would bypass Campaign#should_stop?'s
      # own premature-finalization guard (see memory: "Campaign
      # premature-finalization bug").
      campaign = create(:ai_campaign, account: account)
      ralph_loop.update!(campaign: campaign)

      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "F9-99",
        outcome: "passed", summary: "done"
      })

      expect(result[:success]).to be true
      expect(result[:all_tasks_completed]).to be true
      expect(ralph_loop.reload.status).not_to eq("completed")
    end

    it "does NOT complete the loop while other tasks are still pending" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "F9-100")

      tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "F9-99",
        outcome: "passed", summary: "done"
      })

      expect(ralph_loop.reload.status).not_to eq("completed")
    end

    it "embeds each captured learning mid-run, not only at completion (G12)" do
      extractor = instance_double(Ai::Learning::RalphLearningExtractor)
      allow(Ai::Learning::RalphLearningExtractor).to receive(:new).and_return(extractor)
      # Inc7: the loop/task context (task_key, changed files) is threaded so the
      # extractor can derive tags/importance.
      expect(extractor).to receive(:extract_learning)
        .with(an_instance_of(Ai::RalphLoop), /worker running/, context: hash_including(task_key: "F9-99"))

      tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "F9-99",
        outcome: "failed", summary: "still red", learning: "this area needs the worker running"
      })
    end

    it "records a failed outcome and still captures the learning" do
      result = tool.execute(params: {
        action: "dev_complete_task",
        loop_id: ralph_loop.id,
        task_key: "F9-99",
        outcome: "failed",
        summary: "Spec still red after 3 attempts",
        learning: "This area needs the worker running to reproduce"
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("failed")
      expect(ralph_loop.ralph_iterations.last.status).to eq("failed")
      expect(ralph_loop.reload.learnings.last["text"]).to match(/worker running/)
    end

    it "records a blocked outcome with a blocked error code" do
      result = tool.execute(params: {
        action: "dev_complete_task",
        loop_id: ralph_loop.id,
        task_key: "F9-99",
        outcome: "blocked",
        summary: "Needs an architecture decision on the act-arc"
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("blocked")
      expect(ralph_loop.ralph_iterations.last.error_code).to eq("blocked")
    end

    it "remaps a passed outcome touching a protected path to a human-gated block (G10)" do
      result = tool.execute(params: {
        action: "dev_complete_task",
        loop_id: ralph_loop.id,
        task_key: "F9-99",
        outcome: "passed",
        summary: "Refactored the charge flow",
        files_changed: ["server/app/services/payments/charge.rb"]
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("blocked")
      expect(result[:guardrail][:blocked]).to be true
      expect(result[:guardrail][:violations].first[:file]).to eq("server/app/services/payments/charge.rb")
      expect(ralph_loop.ralph_tasks.find_by(task_key: "F9-99").status).to eq("blocked")
    end

    it "rejects completion of a task that was never claimed" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "unclaimed")

      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "unclaimed", outcome: "passed", summary: "nope"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not in_progress/)
    end

    it "rejects an invalid outcome" do
      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "F9-99", outcome: "shipped", summary: "done"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Invalid outcome/)
    end

    it "requires a summary" do
      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "F9-99", outcome: "passed", summary: ""
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/summary/)
    end
  end

  describe "dev_complete_task applying the linked improvement recommendation (IMP-a091565577cc)" do
    let!(:recommendation) do
      create(:ai_improvement_recommendation, :approved, account: account,
                                                          recommendation_type: "code_lint")
    end
    let!(:task) do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "IMP-99",
                             metadata: { "recommendation_id" => recommendation.id })
    end

    before do
      ralph_loop.update!(status: "running", started_at: Time.current)
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
    end

    it "transitions the linked recommendation to applied when the task passes" do
      # Green evidence required since IMP-f2b3e9a67d11: an unevidenced pass is
      # attested-only and deliberately does NOT close the offer.
      result = tool.execute(params: {
        action: "dev_complete_task",
        loop_id: ralph_loop.id,
        task_key: "IMP-99",
        outcome: "passed",
        summary: "Fixed the lint finding",
        check_results: { "rspec" => "12 examples, 0 failures" }
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("passed")
      expect(recommendation.reload.status).to eq("applied")
      expect(recommendation.applied_at).to be_present
    end

    it "does not touch recommendations on a non-passing outcome" do
      tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "IMP-99",
        outcome: "failed", summary: "still red"
      })

      expect(recommendation.reload.status).to eq("approved")
    end

    it "is safe when a passed task has no recommendation_id" do
      create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop, task_key: "PLAIN-1",
                                            metadata: { "claimed_by" => "user:#{user.id}" })

      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "PLAIN-1",
        outcome: "passed", summary: "no recommendation link here"
      })

      expect(result[:success]).to be true
    end
  end

  describe "dev_complete_task resolving a blocked task (operator disposition)" do
    let!(:blocked_task) do
      create(:ai_ralph_task, :blocked, ralph_loop: ralph_loop, task_key: "BLK-1")
    end

    before { ralph_loop.update!(status: "running", started_at: Time.current) }

    it "resolves a blocked task as passed without re-claiming it" do
      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "BLK-1", outcome: "passed",
        summary: "Already fixed on develop; closing the stale blocked task",
        check_results: { "rspec" => "27 examples, 0 failures" }
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("passed")
      expect(blocked_task.reload.error_message).to be_nil
      iteration = ralph_loop.ralph_iterations.last
      expect(iteration.status).to eq("completed")
      expect(blocked_task.completed_in_iteration).to eq(iteration.iteration_number)
    end

    it "resolves a blocked task as failed" do
      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "BLK-1", outcome: "failed", summary: "Abandoned; not worth fixing"
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("failed")
      expect(ralph_loop.ralph_iterations.last.status).to eq("failed")
    end

    it "resolves a blocked task as skipped" do
      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "BLK-1", outcome: "skipped", summary: "Superseded; won't do"
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("skipped")
      expect(ralph_loop.ralph_iterations.last.status).to eq("skipped")
    end

    # An illegal (status, outcome) pairing must be rejected BEFORE an iteration is
    # created — never half-applied (orphaned iteration + unchanged task).
    it "rejects skipping an in_progress task without orphaning an iteration" do
      create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop, task_key: "IP-1")

      expect do
        result = tool.execute(params: {
          action: "dev_complete_task", loop_id: ralph_loop.id,
          task_key: "IP-1", outcome: "skipped", summary: "nope"
        })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Cannot mark in_progress task as skipped/)
      end.not_to(change { ralph_loop.ralph_iterations.count })
    end

    it "rejects re-blocking an already-blocked task without orphaning an iteration" do
      expect do
        result = tool.execute(params: {
          action: "dev_complete_task", loop_id: ralph_loop.id,
          task_key: "BLK-1", outcome: "blocked", summary: "nope"
        })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Cannot mark blocked task as blocked/)
      end.not_to(change { ralph_loop.ralph_iterations.count })
    end

    it "still rejects completion of a pending (unclaimed) task" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "PEND-1")

      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "PEND-1", outcome: "passed", summary: "nope"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not in_progress or blocked/)
    end
  end

  describe "governance" do
    it "registers the dev.* intervention categories" do
      %w[dev.pull_task dev.complete_task dev.commit_to_branch dev.multi_file_change dev.merge].each do |cat|
        expect(Ai::InterventionPolicy.category_registered?(cat)).to be(true), "expected #{cat} registered"
      end
    end

    it "annotates completions touching more than 5 files (report-only)" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "wide")
      ralph_loop.update!(status: "running", started_at: Time.current)
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "wide",
        outcome: "passed", summary: "broad refactor",
        files_changed: %w[a.rb b.rb c.rb d.rb e.rb f.rb g.rb]
      })

      expect(result[:governance]).to eq(category: "dev.multi_file_change", files_changed: 7)
    end

    it "assesses configuration.completion criteria in queue snapshots" do
      ralph_loop.update!(configuration: {
        "completion" => { "all_tasks_terminal" => true, "max_failed_pct" => 20 }
      })
      create(:ai_ralph_task, :passed, ralph_loop: ralph_loop, task_key: "done")
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "open")
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "decision", execution_type: "human")

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
      completion = result[:loop][:queue][:completion]

      expect(completion[:met]).to be false
      expect(completion[:non_terminal]).to eq(1) # "open" claimed in_progress; human excluded
      expect(completion[:failed_pct]).to eq(0.0)

      done = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "open",
        outcome: "passed", summary: "done"
      })

      # Report-only assessment still surfaces in the queue snapshot...
      expect(done[:queue][:completion][:met]).to be true
      # ...and the dev_next_task terminator now ACTS on it (G5): the loop finishes
      # instead of handing out more work.
      snapshot = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
      expect(snapshot[:halted]).to be true
      expect(snapshot[:reason]).to eq("goal_met")
      expect(ralph_loop.reload.status).to eq("completed")
    end
  end

  describe "context requirements" do
    it "requires a user or agent claimant" do
      anonymous = described_class.new(account: account)

      result = anonymous.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/context required/)
    end

    # BUG-S: an instance principal (mTLS node cert; user AND agent both nil — e.g. a
    # managed dev-cell driving the dev-loop over MCP) had claimant_ref == nil and so
    # was hard-refused at call() line 106 for every dev-loop action. node_instance is
    # injected post-construction by McpPlatformToolRegistrar; claimant_ref now scopes
    # instance claims as "instance:<id>".
    describe "instance principal (BUG-S)" do
      let(:instance) { double("System::NodeInstance", id: "0198abcd-node-instance") }

      it "scopes the claim as instance:<id> when only node_instance is present" do
        tool = described_class.new(account: account)
        tool.node_instance = instance
        expect(tool.send(:claimant_ref)).to eq("instance:0198abcd-node-instance")
      end

      it "no longer refuses dev-loop actions for an instance principal" do
        create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "t")
        tool = described_class.new(account: account)
        tool.node_instance = instance

        result = tool.execute(params: { action: "dev_list_tasks", loop_id: ralph_loop.name })

        expect(result[:success]).to be true
        expect(result[:error]).to be_nil
      end

      it "leaves the user claimant path unchanged (regression)" do
        tool.node_instance = instance # user is already present via let(:tool)
        expect(tool.send(:claimant_ref)).to eq("user:#{user.id}")
      end
    end
  end

  # IMP-f2b3e9a67d11 — the bridge recorded a self-attested "passed" as verified
  # (checks_passed hardcoded true) and flipped the linked offer to applied on
  # it. The platform cannot execute an external executor's suite, so the
  # enforceable contract is evidence adjudication over check_results: a pass
  # whose own tallies ALL show failures is REJECTED outright; a pass with no
  # parseable test evidence records as attested (checks_passed false) and does
  # NOT auto-apply the linked offer; red-first tallies alongside any green
  # tally stay verified (honest red-first evidence must not read as failure).
  describe "dev_complete_task evidence adjudication" do
    let!(:recommendation) do
      create(:ai_improvement_recommendation, :approved, account: account,
                                                        recommendation_type: "code_lint")
    end
    let!(:adj_task) do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "adj-task", priority: 5,
                             metadata: { "recommendation_id" => recommendation.id })
    end

    before { tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id }) }

    def complete_with(check_results)
      params = { action: "dev_complete_task", loop_id: ralph_loop.id,
                 task_key: "adj-task", outcome: "passed", summary: "done" }
      params[:check_results] = check_results if check_results
      tool.execute(params: params)
    end

    it "rejects a passed outcome whose own evidence shows only failing tallies" do
      result = complete_with({ "rspec" => "90 examples, 1 failure" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/contradicted/i)
      expect(adj_task.reload.status).to eq("in_progress")
      expect(recommendation.reload.status).to eq("approved")
    end

    it "records an unevidenced pass as attested and does not auto-apply the linked offer" do
      result = complete_with(nil)

      expect(result[:success]).to be true
      expect(adj_task.reload.status).to eq("passed")
      expect(recommendation.reload.status).to eq("approved")
      expect(Ai::RalphIteration.find_by(ralph_task_id: adj_task.id).checks_passed).to be(false)
    end

    it "verifies a pass whose green tally coexists with red-first evidence" do
      result = complete_with({ "rspec" => "90 examples, 0 failures",
                               "red_first" => "5 examples, 5 failures before the fix" })

      expect(result[:success]).to be true
      expect(recommendation.reload.status).to eq("applied")
      expect(Ai::RalphIteration.find_by(ralph_task_id: adj_task.id).checks_passed).to be(true)
    end
  end

  # IMP-5f8a744b8892 — record_injection! at claim depresses effectiveness until
  # an outcome resolves it, and the drain path never resolved one: at 3
  # injections a learning hard-scored 0.0 (promotion barred, recall ranking
  # inverted), so the corpus degraded in proportion to use. A passed completion
  # must credit exactly the learnings its own claim injected; failed/blocked
  # outcomes leave the injection unresolved (that depression is intended).
  describe "compound-learning credit loop" do
    let!(:learning) do
      create(:ai_compound_learning, account: account, status: "active",
             category: "best_practice", title: "Idempotent reconciliation",
             content: "Widget reconciliation must be idempotent across retries",
             importance_score: 0.8)
    end

    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?)
        .with(:compound_learning_injection, account).and_return(true)
    end

    it "resolves claim-time injections positively when the task passes" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "credit-task", priority: 5,
             description: "Fix widget reconciliation idempotency across retries",
             acceptance_criteria: "Reconciliation is idempotent")

      claim = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
      expect(claim[:success]).to be true
      expect(learning.reload.injection_count).to eq(1)

      task = ralph_loop.ralph_tasks.find_by(task_key: "credit-task")
      expect(task.metadata["injected_learning_ids"]).to eq([ learning.id ])

      # Verified evidence required since IMP-f2b3e9a67d11 — an attested-only
      # pass must not inflate learning effectiveness.
      tool.execute(params: { action: "dev_complete_task", loop_id: ralph_loop.id,
                             task_key: "credit-task", outcome: "passed", summary: "done",
                             check_results: { "rspec" => "8 examples, 0 failures" } })

      expect(learning.reload.positive_outcome_count).to eq(1)
      expect(task.reload.metadata).not_to have_key("injected_learning_ids")
    end

    it "does not credit injections on an attested-only pass" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "attested-task", priority: 5,
             description: "Fix widget reconciliation idempotency across retries",
             acceptance_criteria: "Reconciliation is idempotent")
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      tool.execute(params: { action: "dev_complete_task", loop_id: ralph_loop.id,
                             task_key: "attested-task", outcome: "passed", summary: "trust me" })

      expect(learning.reload.positive_outcome_count).to eq(0)
    end

    it "leaves injections unresolved when the task fails" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "fail-task", priority: 5,
             description: "Fix widget reconciliation idempotency across retries",
             acceptance_criteria: "Reconciliation is idempotent")

      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
      tool.execute(params: { action: "dev_complete_task", loop_id: ralph_loop.id,
                             task_key: "fail-task", outcome: "failed", summary: "did not work" })

      expect(learning.reload.positive_outcome_count).to eq(0)
    end
  end

  describe "dev_update_task" do
    let!(:task) do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "IMP-abc123", priority: 5,
             description: "Original title",
             acceptance_criteria: "Original criteria",
             metadata: { "recommendation_id" => "rec-1", "verifier_evidence" => "proved on HEAD" })
    end

    def update(**params)
      tool.execute(params: { action: "dev_update_task", loop_id: ralph_loop.name,
                             task_key: "IMP-abc123" }.merge(params))
    end

    it "amends the executor-facing brief so a post-promotion direction reaches dev_next_task" do
      result = update(acceptance_criteria: "DELETE the machinery. Do not wire it.")

      expect(result[:success]).to be true
      expect(result[:changed]).to include("acceptance_criteria")
      expect(task.reload.acceptance_criteria).to eq("DELETE the machinery. Do not wire it.")

      claimed = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name })
      expect(claimed[:task][:acceptance_criteria]).to eq("DELETE the machinery. Do not wire it.")
    end

    it "preserves the pre-edit acceptance_criteria so discovery provenance stays recoverable" do
      update(acceptance_criteria: "Rewritten")

      history = task.reload.metadata["operator_edits"]
      expect(history.last["field"]).to eq("acceptance_criteria")
      expect(history.last["previous"]).to eq("Original criteria")
      expect(task.metadata["verifier_evidence"]).to eq("proved on HEAD")
    end

    it "appends attributed notes without disturbing the brief" do
      update(note: "Operator: delete, do not wire")

      expect(task.reload.metadata["operator_notes"].last["note"]).to eq("Operator: delete, do not wire")
      expect(task.metadata["operator_notes"].last["author"]).to eq("user:#{user.id}")
      expect(task.acceptance_criteria).to eq("Original criteria")
    end

    it "edits routing and priority fields" do
      result = update(priority: 25, execution_type: "human", required_capabilities: %w[ruby])

      expect(result[:success]).to be true
      expect(task.reload.priority).to eq(25)
      expect(task.execution_type).to eq("human")
      expect(task.required_capabilities).to eq(%w[ruby])
    end

    # Claimed by ANOTHER principal: an operator overriding an executor, which is
    # the seam's purpose — allowed, but warned, because that executor already
    # holds the old brief. (Self-claimed brief edits are refused outright; see
    # the conflict-of-interest specs below.)
    it "warns when amending an in_progress task whose executor already holds the old brief" do
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name })
      task.reload.update!(metadata: task.metadata.merge("claimed_by" => "agent:other-drain"))

      result = update(acceptance_criteria: "Changed mid-flight")

      expect(result[:success]).to be true
      expect(result[:warning]).to match(/in_progress/)
    end

    it "warns when amending a terminal task that will never be re-delivered" do
      task.update!(status: "passed")

      result = update(note: "post-hoc")

      expect(result[:warning]).to match(/passed/)
    end

    it "ignores an explicit null instead of erasing the field" do
      result = update(description: nil, note: "just a note")

      expect(result[:success]).to be true
      expect(result[:changed]).to eq(["note"])
      expect(task.reload.description).to eq("Original title")
    end

    it "does not erase the brief when acceptance_criteria arrives as null" do
      update(acceptance_criteria: nil, note: "x")

      expect(task.reload.acceptance_criteria).to eq("Original criteria")
    end

    it "refuses executor_type, which is unvalidated and would break task.executor" do
      result = update(executor_type: "Agent")

      expect(result[:success]).to be false
      expect(result[:error]).to match(/executor_type/)
    end

    it "warns that a task amended to execution_type human will never be drained" do
      result = update(execution_type: "human")

      expect(result[:success]).to be true
      expect(result[:warning]).to match(/human/)
    end

    it "refuses a non-Hash delegation_config instead of persisting a later TypeError" do
      result = update(delegation_config: 3600)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/delegation_config/)
      expect { task.reload.execution_timeout }.not_to raise_error
    end

    it "refuses a non-Array required_capabilities" do
      result = update(required_capabilities: "ruby")

      expect(result[:success]).to be false
      expect(task.reload.required_capabilities).not_to eq("ruby")
    end

    it "caps the operator journal so it cannot grow the claim payload without bound" do
      12.times { |i| update(acceptance_criteria: "#{'x' * 400}#{i}") }

      expect(task.reload.metadata["operator_edits"].size)
        .to be <= Ai::RalphTask::OPERATOR_JOURNAL_LIMIT
    end

    # IMP-3c15b871f6bd. The abuse shape is self-serving: claim a task, weaken the
    # brief you are about to be judged against, report passed — a :verified
    # adjudication then auto-applies the linked offer. Refuse the brief edit only
    # when the SAME principal currently holds the claim.
    it "refuses to let the current claimant rewrite the brief it will be judged against" do
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name })

      result = update(acceptance_criteria: "trivially satisfiable")

      expect(result[:success]).to be false
      expect(result[:error]).to match(/claimed by you/i)
      expect(task.reload.acceptance_criteria).to eq("Original criteria")
    end

    it "refuses a self-claimed description rewrite for the same reason" do
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name })

      expect(update(description: "something easier")[:success]).to be false
    end

    it "still allows the claimant to append a note — that cannot weaken the brief" do
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name })

      result = update(note: "blocked on a missing fixture")

      expect(result[:success]).to be true
      expect(task.reload.metadata["operator_notes"].last["note"]).to eq("blocked on a missing fixture")
    end

    it "allows an operator to amend a task claimed by someone else" do
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name })
      task.reload.update!(metadata: task.metadata.merge("claimed_by" => "agent:someone-else"))

      expect(update(acceptance_criteria: "operator amendment")[:success]).to be true
    end

    it "rejects an unknown field rather than silently dropping it" do
      result = update(status: "passed")

      expect(result[:success]).to be false
      expect(result[:error]).to match(/status/)
    end

    it "requires at least one change" do
      expect(update[:success]).to be false
    end

    it "validates the edit instead of persisting garbage" do
      result = update(execution_type: "telepathy")

      expect(result[:success]).to be false
      expect(task.reload.execution_type).not_to eq("telepathy")
    end

    it "returns not-found for an unknown task key" do
      result = tool.execute(params: { action: "dev_update_task", loop_id: ralph_loop.name,
                                      task_key: "nope", note: "x" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end
  end
end
