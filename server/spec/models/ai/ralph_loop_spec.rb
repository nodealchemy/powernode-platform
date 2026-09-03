# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::RalphLoop, type: :model do
  let(:account) { create(:account) }
  let(:loop_record) { create(:ai_ralph_loop, account: account, current_iteration: 0) }

  # ==========================================================================
  # Tier-2(c) §5: atomic loop-row state writes. These previously read-modify-
  # wrote without a lock and drifted / lost entries under concurrency.
  # ==========================================================================
  describe "#increment_iteration!" do
    it "increments the iteration counter by one" do
      expect { loop_record.increment_iteration! }
        .to change { loop_record.reload.current_iteration }.from(0).to(1)
    end

    it "recovers from counter drift using the max completed iteration" do
      create(:ai_ralph_iteration, ralph_loop: loop_record, iteration_number: 5)
      loop_record.increment_iteration!
      expect(loop_record.reload.current_iteration).to eq(5)
    end

    it "serializes the update under a row lock" do
      expect(loop_record).to receive(:with_lock).and_call_original
      loop_record.increment_iteration!
    end
  end

  # IMP-7f415874c14a: the jsonb append is RETIRED. #add_learning is kept as the
  # public API but now back-fills the surviving sink — the producing iteration's
  # `learning_extracted` — and never touches the loop row. Full coverage lives in
  # spec/models/ai/ralph_loop_learning_write_retirement_spec.rb.
  describe "#add_learning" do
    it "records the learning on the producing iteration's row, not the loop array" do
      create(:ai_ralph_iteration, ralph_loop: loop_record, iteration_number: 3)
      loop_record.update!(current_iteration: 7)

      loop_record.add_learning("Discovered a flaky spec", context: { iteration: 3, task_key: "IMP-1" })

      expect(loop_record.ralph_iterations.find_by(iteration_number: 3).learning_extracted)
        .to eq("Discovered a flaky spec")
      expect(loop_record.reload.learnings).to eq([])
    end

    it "falls back to the loop counter only when the caller supplies no iteration" do
      loop_record.update!(current_iteration: 5)
      create(:ai_ralph_iteration, ralph_loop: loop_record, iteration_number: 5)

      loop_record.add_learning("no iteration context")

      expect(loop_record.ralph_iterations.find_by(iteration_number: 5).learning_extracted)
        .to eq("no iteration context")
    end

    it "scrubs secrets out of the learning text before persisting (G15)" do
      create(:ai_ralph_iteration, ralph_loop: loop_record, iteration_number: 1)

      loop_record.add_learning('Set api_key=sk-supersecretvalue123 in the env', context: { iteration: 1 })

      text = loop_record.ralph_iterations.find_by(iteration_number: 1).learning_extracted
      expect(text).not_to include("sk-supersecretvalue123")
      expect(text).to match(/\[REDACTED/)
    end
  end

  # ==========================================================================
  # IMP-44964469b565 — the recency channel reads from ai_ralph_iterations, not
  # the loop-level jsonb array. The array is STILL WRITTEN; only the READ moved,
  # so the switch stays reversible while both channels are populated.
  # ==========================================================================
  describe "#recent_learnings" do
    let(:record) { create(:ai_ralph_loop, account: account, current_iteration: 0) }

    # Interleaved NULL learning_extracted rows are the production shape (142 of
    # 496 rows carry none). They must be SKIPPED WITHOUT CONSUMING THE LIMIT —
    # a fixture where every row carries a learning hides that off-by-one.
    def seed_interleaved!
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 1, learning_extracted: "oldest")
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 2, learning_extracted: nil)
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 3, learning_extracted: "middle")
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 4, learning_extracted: nil)
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 5, learning_extracted: nil)
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 6, learning_extracted: "newest")
    end

    it "returns the iteration rows' learnings oldest-first, the newest LAST" do
      seed_interleaved!

      expect(record.recent_learnings.map { |l| l["text"] }).to eq(%w[oldest middle newest])
    end

    # The orientation the three readers render (TaskExecutor#format_learnings,
    # IterationExecution#format_learnings, DevLoopTool#iteration_context) is the
    # one `(learnings || []).last(limit)` produced. DESC is the SELECTION of the
    # newest k; the result is reversed back. Pinning it here because flipping it
    # would silently reverse every prompt's "Previous Learnings" block.
    it "keeps only the newest `limit` learnings, skipping NULL rows without spending the limit" do
      seed_interleaved!

      expect(record.recent_learnings(limit: 2).map { |l| l["text"] }).to eq(%w[middle newest])
    end

    it "carries the jsonb entry shape the existing readers index" do
      task = create(:ai_ralph_task, ralph_loop: record, task_key: "IMP-shape")
      create(:ai_ralph_iteration, :completed, ralph_loop: record, ralph_task: task,
             iteration_number: 9, learning_extracted: "Eager-load before iterating")

      entry = record.recent_learnings.last

      expect(entry["text"]).to eq("Eager-load before iterating")
      expect(entry["iteration"]).to eq(9)
      expect(entry["timestamp"]).to be_present
      expect(entry["context"]).to eq({ "iteration" => 9, "task_key" => "IMP-shape" })
      # NOT enriched: iteration rows carry these, array entries never did.
      expect(entry.keys).to match_array(%w[text iteration timestamp context])
    end

    it "ignores an iteration row whose learning_extracted is blank" do
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 1, learning_extracted: "")
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 2, learning_extracted: "kept")

      expect(record.recent_learnings.map { |l| l["text"] }).to eq(["kept"])
    end

    it "returns [] for a loop with no iteration rows at all" do
      expect(record.recent_learnings).to eq([])
    end

    # ---- SOURCE ORACLE, half A -------------------------------------------
    # Clearing the loop-level array must NOT affect the read. Alone this proves
    # nothing (an empty-tolerant array read would also pass) — it is only
    # meaningful paired with half B below.
    it "still reads when the loop-level learnings array is empty (source oracle A)" do
      seed_interleaved!
      record.update!(learnings: [])

      expect(record.reload.recent_learnings.map { |l| l["text"] }).to eq(%w[oldest middle newest])
    end

    # ---- SOURCE ORACLE, half B -------------------------------------------
    # Clearing learning_extracted must empty the read EVEN THOUGH the array is
    # fully populated. Alone this passes for code that reads neither; paired
    # with half A it pins the source to the iteration rows.
    it "goes empty when learning_extracted is cleared, array notwithstanding (source oracle B)" do
      seed_interleaved!
      record.update!(learnings: [ { "text" => "still in the legacy array", "iteration" => 6,
                                    "timestamp" => Time.current.iso8601, "context" => {} } ])
      record.ralph_iterations.update_all(learning_extracted: nil)

      expect(record.reload.learnings).to be_present
      expect(record.recent_learnings).to eq([])
    end

    # ---- #reset! interaction ---------------------------------------------
    # DECISION (IMP-44964469b565): empty-after-reset is CORRECT and deliberate.
    # A reset is "start this run over" — the recency channel is per-run context,
    # so it should start empty, exactly as it does for a brand-new loop.
    # Nothing is lost: IMP-7f415874c14a moved the preservation onto the channel
    # that is actually read — #reset! captures #learning_entries BEFORE its
    # delete_all and hands them to #extract_compound_learnings, so they land in the
    # durable CompoundLearning store and come back as `relevant_learnings` on the
    # next claim. Pinned here so it is a decision, not a production discovery.
    it "goes empty after #reset!, the doomed learnings having been harvested" do
      terminal = create(:ai_ralph_loop, :failed, account: account, current_iteration: 4)
      create(:ai_ralph_iteration, ralph_loop: terminal, iteration_number: 1,
             learning_extracted: "Webhook receivers must return 202, never 500")
      expect(terminal.recent_learnings.map { |l| l["text"] })
        .to eq(["Webhook receivers must return 202, never 500"])
      harvested = nil
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
        .to receive(:extract) { |_x, _loop, entries: nil| harvested = Array(entries).map { |e| e["text"] } }

      terminal.reset!
      terminal.reload

      expect(terminal.recent_learnings).to eq([])
      expect(harvested).to eq(["Webhook receivers must return 202, never 500"])
    end
  end

  describe "#real_test_execution?" do
    it "is ON by default (G1: the gate is opt-out, not opt-in)" do
      expect(loop_record.real_test_execution?).to be true
    end

    it "stays ON when the flag is set true without a test command (auto-detected)" do
      loop_record.update!(configuration: { "real_test_execution" => true })
      expect(loop_record.real_test_execution?).to be true
    end

    it "is OFF only when explicitly opted out" do
      loop_record.update!(configuration: { "real_test_execution" => false })
      expect(loop_record.real_test_execution?).to be false
    end
  end

  describe "#test_command" do
    it "is nil when unset (TestVerificationService auto-detects the framework)" do
      expect(loop_record.test_command).to be_nil
    end

    it "returns the configured command when present" do
      loop_record.update!(configuration: { "test_command" => "bundle exec rspec" })
      expect(loop_record.test_command).to eq("bundle exec rspec")
    end

    it "treats a blank command as nil" do
      loop_record.update!(configuration: { "test_command" => "  " })
      expect(loop_record.test_command).to be_nil
    end
  end

  describe "#repository_full_name" do
    it "derives owner/repo from an https URL with a .git suffix" do
      loop_record.update!(repository_url: "https://git.example.com/acme/widget.git")
      expect(loop_record.repository_full_name).to eq("acme/widget")
    end

    it "derives owner/repo from an ssh:// URL" do
      loop_record.update!(repository_url: "ssh://git@git.example.com/acme/widget.git")
      expect(loop_record.repository_full_name).to eq("acme/widget")
    end

    it "is nil when no repository_url is set" do
      loop_record.update_column(:repository_url, nil)
      expect(loop_record.repository_full_name).to be_nil
    end
  end

  # G5: goal-driven completion + runtime-aware hard caps. These predicates are the
  # single source of truth shared by the dev-loop pull path and the platform executor.
  describe "G5 stop conditions" do
    describe "#completion_status / #goal_met?" do
      it "is nil/false when no completion criteria are configured" do
        expect(loop_record.completion_status).to be_nil
        expect(loop_record.goal_met?).to be false
      end

      it "is met once every executable task is terminal within the failure budget (humans excluded)" do
        loop_record.update!(configuration: { "completion" => { "all_tasks_terminal" => true, "max_failed_pct" => 20 } })
        create(:ai_ralph_task, :passed, ralph_loop: loop_record, task_key: "a")
        open = create(:ai_ralph_task, ralph_loop: loop_record, task_key: "b")
        create(:ai_ralph_task, ralph_loop: loop_record, task_key: "h", execution_type: "human")

        expect(loop_record.goal_met?).to be false # "b" still pending
        open.update!(status: "passed")

        assessment = loop_record.completion_status
        expect(assessment[:met]).to be true
        expect(assessment[:non_terminal]).to eq(0)
        expect(loop_record.halt_reason).to eq("goal_met")
      end
    end

    describe "#wall_clock_exceeded?" do
      it "trips once started_at is older than max_wall_clock_seconds" do
        loop_record.update!(status: "running", started_at: 2.hours.ago,
                            configuration: { "max_wall_clock_seconds" => 60 })
        expect(loop_record.wall_clock_exceeded?).to be true
        expect(loop_record.runtime_cap_reason).to eq("wall_clock_exceeded")
        expect(loop_record.halt_reason).to eq("wall_clock_exceeded")
      end

      it "does not trip before the budget elapses or when unset" do
        loop_record.update!(status: "running", started_at: 5.seconds.ago,
                            configuration: { "max_wall_clock_seconds" => 3600 })
        expect(loop_record.wall_clock_exceeded?).to be false

        loop_record.update!(configuration: {}) # no cap
        expect(loop_record.wall_clock_exceeded?).to be false
      end
    end

    describe "#token_cap_exceeded? / #cost_cap_exceeded? (metered loops only)" do
      it "caps a metered (platform) loop over its token budget" do
        metered = create(:ai_ralph_loop, account: account, driver_kind: "platform_agent",
                         configuration: { "max_tokens" => 1000 })
        create(:ai_ralph_iteration, ralph_loop: metered, iteration_number: 1,
                                    tokens_input: 600, tokens_output: 600)

        expect(metered.token_cap_exceeded?).to be true
        expect(metered.runtime_cap_reason).to eq("token_cap_exceeded")
      end

      it "caps a metered loop over its cost budget" do
        metered = create(:ai_ralph_loop, account: account, driver_kind: "platform_agent",
                         configuration: { "max_cost" => 1.0 })
        create(:ai_ralph_iteration, ralph_loop: metered, iteration_number: 1, cost: 1.25)

        expect(metered.cost_cap_exceeded?).to be true
        expect(metered.runtime_cap_reason).to eq("cost_cap_exceeded")
      end

      it "leaves a flat-rate claude_code loop UNCAPPED over the same nominal spend (by design)" do
        flat = create(:ai_ralph_loop, account: account, driver_kind: "claude_code",
                      configuration: { "max_tokens" => 1000, "max_cost" => 1.0 })
        create(:ai_ralph_iteration, ralph_loop: flat, iteration_number: 1,
                                    tokens_input: 600, tokens_output: 600, cost: 1.25)

        expect(flat.token_cap_exceeded?).to be false
        expect(flat.cost_cap_exceeded?).to be false
        expect(flat.runtime_cap_reason).to be_nil
        expect(flat.halt_reason).to be_nil
      end
    end

    describe "#halt_reason ordering" do
      it "prefers the iteration cap over runtime caps when both trip (no goal configured)" do
        loop_record.update!(status: "running", started_at: 2.hours.ago,
                            max_iterations: 1, current_iteration: 5,
                            configuration: { "max_wall_clock_seconds" => 60 })
        expect(loop_record.halt_reason).to eq("max_iterations_reached")
      end
    end
  end

  describe "G9 vendor-neutral flat-rate executor taxonomy" do
    it "accepts external_cli as a valid driver_kind alongside claude_code" do
      Ai::RalphLoop::FLAT_RATE_DRIVER_KINDS.each do |kind|
        expect(build(:ai_ralph_loop, account: account, driver_kind: kind)).to be_valid
      end
    end

    describe "#flat_rate_executor?" do
      it "is true for claude_code AND external_cli" do
        Ai::RalphLoop::FLAT_RATE_DRIVER_KINDS.each do |kind|
          loop_rec = build(:ai_ralph_loop, account: account, driver_kind: kind)
          expect(loop_rec.flat_rate_executor?).to be(true), "expected #{kind} to be flat-rate"
          expect(loop_rec.platform_driven?).to be false
        end
      end

      it "is false for metered platform_* loops" do
        Ai::RalphLoop::PLATFORM_DRIVER_KINDS.each do |kind|
          loop_rec = build(:ai_ralph_loop, account: account, driver_kind: kind)
          expect(loop_rec.flat_rate_executor?).to be(false), "expected #{kind} not to be flat-rate"
          expect(loop_rec.platform_driven?).to be true
        end
      end

      it "keeps claude_code_driven? specific to claude_code (back-compat)" do
        expect(build(:ai_ralph_loop, account: account, driver_kind: "claude_code").claude_code_driven?).to be true
        expect(build(:ai_ralph_loop, account: account, driver_kind: "external_cli").claude_code_driven?).to be false
      end
    end

    describe "#executor_vendor" do
      it "defaults the claude_code instance to anthropic" do
        expect(build(:ai_ralph_loop, account: account, driver_kind: "claude_code").executor_vendor).to eq("anthropic")
      end

      it "resolves the configured vendor label for external_cli" do
        loop_rec = build(:ai_ralph_loop, account: account, driver_kind: "external_cli",
                                         configuration: { "executor_vendor" => "grok" })
        expect(loop_rec.executor_vendor).to eq("grok")
      end

      it "lets configuration override the claude_code default" do
        loop_rec = build(:ai_ralph_loop, account: account, driver_kind: "claude_code",
                                         configuration: { "executor_vendor" => "claude" })
        expect(loop_rec.executor_vendor).to eq("claude")
      end

      it "falls back to a generic label for an unlabelled external_cli" do
        expect(build(:ai_ralph_loop, account: account, driver_kind: "external_cli").executor_vendor).to eq("external_cli")
      end

      it "is nil for a metered platform loop (no external CLI vendor)" do
        expect(build(:ai_ralph_loop, account: account, driver_kind: "platform_agent").executor_vendor).to be_nil
      end
    end

    it "leaves a flat-rate external_cli loop token/cost-UNCAPPED, like claude_code" do
      flat = create(:ai_ralph_loop, account: account, driver_kind: "external_cli",
                    configuration: { "executor_vendor" => "grok", "max_tokens" => 1000, "max_cost" => 1.0 })
      create(:ai_ralph_iteration, ralph_loop: flat, iteration_number: 1,
                                  tokens_input: 600, tokens_output: 600, cost: 1.25)

      expect(flat.token_cap_exceeded?).to be false
      expect(flat.cost_cap_exceeded?).to be false
      expect(flat.runtime_cap_reason).to be_nil
      expect(flat.halt_reason).to be_nil
    end

    it "keeps the metered scope to platform_* loops only (external_cli excluded)" do
      cc   = create(:ai_ralph_loop, account: account, driver_kind: "claude_code")
      ext  = create(:ai_ralph_loop, account: account, driver_kind: "external_cli")
      plat = create(:ai_ralph_loop, account: account, driver_kind: "platform_agent")

      metered = Ai::RalphLoop.metered
      expect(metered).to include(plat)
      expect(metered).not_to include(cc, ext)
    end
  end

  # ==========================================================================
  # Ai::RalphLoopConcerns::StateMachine — lifecycle transitions, guards,
  # repeating-task completion block, and reset!.
  # ==========================================================================
  describe "state machine" do
    describe "#start!" do
      it "transitions pending -> running and stamps started_at" do
        loop_record.start!
        loop_record.reload

        expect(loop_record.status).to eq("running")
        expect(loop_record.started_at).to be_present
      end

      %i[running paused completed failed cancelled].each do |state|
        it "refuses to start from #{state}" do
          record = create(:ai_ralph_loop, state, account: account)

          expect { record.start! }
            .to raise_error(Ai::RalphLoop::InvalidTransitionError, /Cannot start loop in #{state} status/)
        end
      end
    end

    describe "#pause! / #resume!" do
      it "pauses a running loop and resumes it back to running" do
        record = create(:ai_ralph_loop, :running, account: account)

        record.pause!
        expect(record.reload.status).to eq("paused")

        record.resume!
        expect(record.reload.status).to eq("running")
      end

      it "refuses to pause a loop that is not running" do
        expect { loop_record.pause! }
          .to raise_error(Ai::RalphLoop::InvalidTransitionError, /Cannot pause/)
      end

      it "refuses to resume a loop that is not paused" do
        record = create(:ai_ralph_loop, :running, account: account)

        expect { record.resume! }
          .to raise_error(Ai::RalphLoop::InvalidTransitionError, /Cannot resume/)
      end
    end

    describe "#complete!" do
      it "transitions running -> completed, stamping completed_at and merging the final result" do
        record = create(:ai_ralph_loop, :running, account: account, configuration: { "keep" => "me" })

        record.complete!(result: { "tasks_passed" => 3 })
        record.reload

        expect(record.status).to eq("completed")
        expect(record.completed_at).to be_present
        expect(record.configuration["keep"]).to eq("me")
        expect(record.configuration["final_result"]).to eq({ "tasks_passed" => 3 })
      end

      it "completes from paused as well" do
        record = create(:ai_ralph_loop, :paused, account: account)

        expect { record.complete! }.to change { record.reload.status }.from("paused").to("completed")
      end

      it "refuses to complete a pending loop" do
        expect { loop_record.complete! }
          .to raise_error(Ai::RalphLoop::InvalidTransitionError, /Cannot complete/)
      end

      it "BLOCKS completion while repeating tasks exist (loop stays running, no error)" do
        record = create(:ai_ralph_loop, :running, account: account)
        create(:ai_ralph_task, ralph_loop: record, repeating: true)

        expect(Rails.logger).to receive(:warn).with(a_string_including("Blocked completion"))
        expect { record.complete! }.not_to raise_error

        expect(record.reload.status).to eq("running")
        expect(record.completed_at).to be_nil
      end
    end

    describe "#fail!" do
      %i[pending running paused].each do |state|
        it "fails from #{state} recording the error details" do
          record = create(:ai_ralph_loop, state, account: account)

          record.fail!(error_message: "boom", error_code: "E_BOOM", error_details: { "step" => 4 })
          record.reload

          expect(record.status).to eq("failed")
          expect(record.completed_at).to be_present
          expect(record.error_message).to eq("boom")
          expect(record.error_code).to eq("E_BOOM")
          expect(record.error_details).to eq({ "step" => 4 })
        end
      end

      it "refuses to fail an already-terminal loop" do
        record = create(:ai_ralph_loop, :completed, account: account)

        expect { record.fail!(error_message: "late") }
          .to raise_error(Ai::RalphLoop::InvalidTransitionError, /Cannot fail/)
      end
    end

    describe "#cancel!" do
      it "cancels any non-terminal loop and records the reason" do
        record = create(:ai_ralph_loop, :running, account: account)

        record.cancel!(reason: "operator abort")
        record.reload

        expect(record.status).to eq("cancelled")
        expect(record.completed_at).to be_present
        expect(record.configuration["cancellation_reason"]).to eq("operator abort")
      end

      %i[completed failed cancelled].each do |state|
        it "refuses to cancel a #{state} loop" do
          record = create(:ai_ralph_loop, state, account: account)

          expect { record.cancel! }
            .to raise_error(Ai::RalphLoop::InvalidTransitionError, /Cannot cancel/)
        end
      end
    end

    describe "#reset!" do
      let(:record) { create(:ai_ralph_loop, :failed, account: account, current_iteration: 4) }

      before do
        create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 1)
        create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 2)
      end

      it "clears iteration history and restores the loop to a clean pending state" do
        record.reset!
        record.reload

        expect(record.status).to eq("pending")
        expect(record.current_iteration).to eq(0)
        expect(record.started_at).to be_nil
        expect(record.completed_at).to be_nil
        expect(record.error_message).to be_nil
        expect(record.error_code).to be_nil
        expect(record.error_details).to eq({})
        expect(record.ralph_iterations.count).to eq(0)
      end

      it "resets non-skipped tasks to pending but preserves intentionally skipped tasks" do
        passed = create(:ai_ralph_task, :passed, ralph_loop: record, execution_attempts: 3)
        failed = create(:ai_ralph_task, :failed, ralph_loop: record, execution_attempts: 2)
        skipped = create(:ai_ralph_task, :skipped, ralph_loop: record)

        record.reset!

        expect(passed.reload).to have_attributes(
          status: "pending", execution_attempts: 0, completed_in_iteration: nil, iteration_completed_at: nil
        )
        expect(failed.reload).to have_attributes(status: "pending", error_message: nil, error_code: nil)
        expect(skipped.reload.status).to eq("skipped")
      end

      # IMP-3acfff02a847 / IMP-7f415874c14a: reset! is a do-over of the RUN, not
      # amnesia about what the run TAUGHT. delete_all destroys
      # ai_ralph_iterations.learning_extracted, now the ONLY per-iteration record.
      # The preservation used to back-fill the loop-level jsonb array; that array is
      # no longer read, so it moved to the durable CompoundLearning store. Both
      # directions are asserted on purpose: a reset! that simply stopped deleting
      # anything would satisfy the survival assertion alone.
      it "harvests a learning carried only by an iteration row, then destroys the row" do
        record.ralph_iterations.find_by(iteration_number: 2)
              .update!(learning_extracted: "Webhook receivers must return 202, never 500")
        harvested = nil
        allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
          .to receive(:extract) { |_x, _loop, entries: nil| harvested = Array(entries) }

        record.reset!
        record.reload

        # 1. the learning reached the durable channel, attributed to its iteration
        expect(harvested.map { |l| l["text"] })
          .to include("Webhook receivers must return 202, never 500")
        expect(harvested.last["iteration"]).to eq(2)
        # 2. and the iteration rows are genuinely gone, not merely detached
        expect(record.ralph_iterations.count).to eq(0)
        expect(Ai::RalphIteration.where(ralph_loop_id: record.id).count).to eq(0)
      end

      # The harvest is idempotent (near-duplicate dedup in CompoundLearningService),
      # which is what makes resetting a loop #complete! already harvested — or
      # resetting the same loop twice — safe without a dedupe pass of its own. That
      # idempotence is what replaced #preserve_iteration_learnings!'s text dedupe.
      it "does not duplicate a learning the durable store already holds" do
        allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
        record.ralph_iterations.find_by(iteration_number: 1)
              .update!(learning_extracted: "Eager-load before iterating an association")
        record.extract_compound_learnings

        expect { record.reset! }.not_to change(Ai::CompoundLearning, :count)
      end

      it "leaves the retired jsonb column dormant and empty" do
        allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
        record.ralph_iterations.find_by(iteration_number: 1)
              .update!(learning_extracted: "Nothing may be written back to the dead column")

        record.reset!

        expect(record.reload.learnings).to eq([])
      end

      %i[pending running paused].each do |state|
        it "refuses to reset a non-terminal (#{state}) loop" do
          live = create(:ai_ralph_loop, state, account: account)

          expect { live.reset! }
            .to raise_error(Ai::RalphLoop::InvalidTransitionError, /Cannot reset/)
        end
      end
    end

    # IMP-957902bf8474: a loop that drains its queue goes `completed`, which is
    # terminal — halt_reason then returns "loop_completed" forever, and the ONLY
    # terminal-legal transition was reset!, which is destructive (drops iteration
    # history via ralph_iterations.delete_all, and requeues every non-skipped
    # task to pending). #reopen! is the non-destructive escape hatch: terminal ->
    # running, preserving both — for a loop whose "completion" was just the
    # queue running dry, not a deliberate do-over.
    describe "#reopen!" do
      it "moves a completed loop back to running and clears completed_at" do
        record = create(:ai_ralph_loop, :completed, account: account)

        record.reopen!
        record.reload

        expect(record.status).to eq("running")
        expect(record.completed_at).to be_nil
      end

      it "preserves iteration history — contrast with reset!, which clears it" do
        record = create(:ai_ralph_loop, :completed, account: account)
        create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 1)
        create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 2)

        record.reopen!

        expect(record.ralph_iterations.count).to eq(2)
      end

      it "moves no passed task back to pending, and leaves skipped tasks alone — " \
         "contrast with #reset! above, which resets non-skipped tasks to pending" do
        record = create(:ai_ralph_loop, :completed, account: account)
        passed = create(:ai_ralph_task, :passed, ralph_loop: record, execution_attempts: 3)
        skipped = create(:ai_ralph_task, :skipped, ralph_loop: record)

        record.reopen!

        expect(passed.reload).to have_attributes(status: "passed", execution_attempts: 3)
        expect(skipped.reload.status).to eq("skipped")
      end

      %i[completed failed cancelled].each do |state|
        it "reopens a #{state} loop to running" do
          record = create(:ai_ralph_loop, state, account: account)

          record.reopen!

          expect(record.reload.status).to eq("running")
        end
      end

      %i[pending running paused].each do |state|
        it "refuses to reopen a non-terminal (#{state}) loop" do
          live = create(:ai_ralph_loop, state, account: account)

          expect { live.reopen! }
            .to raise_error(Ai::RalphLoop::InvalidTransitionError, /Cannot reopen/)
        end
      end
    end

    describe "state predicates" do
      it "classifies terminal vs in-progress statuses" do
        expect(create(:ai_ralph_loop, :completed, account: account)).to be_terminal
        expect(create(:ai_ralph_loop, :failed, account: account)).to be_terminal
        expect(create(:ai_ralph_loop, :cancelled, account: account)).to be_terminal
        expect(create(:ai_ralph_loop, :running, account: account)).to be_in_progress
        expect(loop_record).to be_in_progress
      end

      it "reports max_iterations_reached? only when a positive cap is hit" do
        expect(create(:ai_ralph_loop, account: account, max_iterations: 3, current_iteration: 3))
          .to be_max_iterations_reached
        expect(create(:ai_ralph_loop, account: account, max_iterations: 3, current_iteration: 2))
          .not_to be_max_iterations_reached
        expect(create(:ai_ralph_loop, account: account, max_iterations: 0, current_iteration: 99))
          .not_to be_max_iterations_reached
      end
    end
  end
end
