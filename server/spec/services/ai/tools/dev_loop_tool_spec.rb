# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::DevLoopTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "dev-audit-test") }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("dev_loop")
      expect(defn[:parameters][:action][:required]).to be true
    end

    it "exposes the bridge actions" do
      expect(described_class.action_definitions.keys)
        .to contain_exactly("dev_next_task", "dev_complete_task", "delegate_ralph_task", "dev_list_tasks")
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

    it "is idempotent — re-claiming returns the same in-progress task" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "only")

      first = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
      second = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(first[:reclaimed]).to be false
      expect(second[:reclaimed]).to be true
      expect(second[:task][:task_key]).to eq("only")
      expect(ralph_loop.ralph_tasks.in_progress.count).to eq(1)
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
        "guardrails" => ["one task per iteration"]
      })
      create(:ai_ralph_task, ralph_loop: ralph_loop)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:loop][:loop_spec_path]).to eq(".claude/loops/dev-audit/PROMPT.md")
      expect(result[:loop][:guardrails]).to eq(["one task per iteration"])
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

    it "embeds each captured learning mid-run, not only at completion (G12)" do
      extractor = instance_double(Ai::Learning::RalphLearningExtractor)
      allow(Ai::Learning::RalphLearningExtractor).to receive(:new).and_return(extractor)
      expect(extractor).to receive(:extract_learning).with(an_instance_of(Ai::RalphLoop), /worker running/)

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

      tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "open",
        outcome: "passed", summary: "done"
      })
      snapshot = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(snapshot[:queue_empty]).to be true
      expect(snapshot[:queue][:completion][:met]).to be true
    end
  end

  describe "context requirements" do
    it "requires a user or agent claimant" do
      anonymous = described_class.new(account: account)

      result = anonymous.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/context required/)
    end
  end
end
