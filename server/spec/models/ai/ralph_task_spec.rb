# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::RalphTask, type: :model do
  let(:account) { create(:account) }
  let(:loop_record) { create(:ai_ralph_loop, account: account) }

  # ==========================================================================
  # Tier-2(c): revert tracking — the ground-truth signal for the ungameable
  # net_improvement_velocity / per-kind revert_rate metric.
  # ==========================================================================
  describe "revert tracking (Tier-2c)" do
    describe "#revert!" do
      let(:task) { create(:ai_ralph_task, :passed, ralph_loop: loop_record) }

      it "records reverted_at + reason without disturbing the terminal status" do
        task.revert!(reason: "regressed prod")
        task.reload

        expect(task.reverted?).to be true
        expect(task.reverted_at).to be_within(2.seconds).of(Time.current)
        expect(task.revert_reason).to eq("regressed prod")
        expect(task.status).to eq("passed") # history stays truthful
      end
    end

    describe "#unrevert!" do
      let(:task) do
        create(:ai_ralph_task, :passed, ralph_loop: loop_record,
               reverted_at: Time.current, revert_reason: "x")
      end

      it "clears the revert flag" do
        task.unrevert!
        expect(task.reload.reverted?).to be false
        expect(task.revert_reason).to be_nil
      end
    end

    describe "#durable?" do
      it "is true for a matured, non-reverted pass" do
        task = create(:ai_ralph_task, :passed, ralph_loop: loop_record, iteration_completed_at: 10.days.ago)
        expect(task.durable?).to be true
      end

      it "is false within the observation window" do
        task = create(:ai_ralph_task, :passed, ralph_loop: loop_record, iteration_completed_at: 1.day.ago)
        expect(task.durable?).to be false
      end

      it "is false once reverted" do
        task = create(:ai_ralph_task, :passed, ralph_loop: loop_record, iteration_completed_at: 10.days.ago)
        task.revert!(reason: "bad")
        expect(task.durable?).to be false
      end

      it "is false for non-passed tasks" do
        task = create(:ai_ralph_task, :failed, ralph_loop: loop_record)
        expect(task.durable?).to be false
      end
    end

    describe "scopes" do
      let!(:durable_task) { create(:ai_ralph_task, :passed, ralph_loop: loop_record, iteration_completed_at: 10.days.ago) }
      let!(:fresh_pass) { create(:ai_ralph_task, :passed, ralph_loop: loop_record, iteration_completed_at: 1.day.ago) }
      let!(:reverted_task) do
        create(:ai_ralph_task, :passed, ralph_loop: loop_record, iteration_completed_at: 10.days.ago)
          .tap { |t| t.revert!(reason: "bad") }
      end

      it ".reverted / .not_reverted partition by reverted_at" do
        expect(described_class.reverted).to include(reverted_task)
        expect(described_class.reverted).not_to include(durable_task, fresh_pass)
        expect(described_class.not_reverted).to include(durable_task, fresh_pass)
        expect(described_class.not_reverted).not_to include(reverted_task)
      end

      it ".durable returns only matured, non-reverted passes" do
        expect(described_class.durable).to include(durable_task)
        expect(described_class.durable).not_to include(fresh_pass, reverted_task)
      end
    end
  end

  # ==========================================================================
  # Tier-2(c): ungameable improvement metric
  # ==========================================================================
  describe ".improvement_scoreboard" do
    let(:loop_record) { create(:ai_ralph_loop, account: account) }

    def imp_task(kind:, status: "passed", completed: 10.days.ago, reverted: false, files: 1)
      task = create(:ai_ralph_task, ralph_loop: loop_record, status: status,
                    iteration_completed_at: (status == "passed" ? completed : nil),
                    metadata: { "kind" => kind, "blast_radius" => files })
      task.revert!(reason: "bad") if reverted
      task
    end

    it "reports per-kind completed / reverted / durable / revert_rate" do
      imp_task(kind: "dead_code")                   # durable pass
      imp_task(kind: "dead_code", reverted: true)   # reverted pass
      imp_task(kind: "code_lint", status: "failed") # not a completion

      board = described_class.improvement_scoreboard(account: account)
      dead = board[:per_kind]["dead_code"]
      expect(dead[:completed]).to eq(2)
      expect(dead[:reverted]).to eq(1)
      expect(dead[:durable]).to eq(1)
      expect(dead[:revert_rate]).to eq(0.5)
    end

    it "flags a kind as throttled when its revert_rate crosses the threshold" do
      3.times { imp_task(kind: "code_duplication", reverted: true) }
      imp_task(kind: "code_duplication") # 1 durable of 4 completed -> revert_rate 0.75

      board = described_class.improvement_scoreboard(account: account)
      expect(board[:per_kind]["code_duplication"][:throttled]).to be true
    end

    it "computes a revert-adjusted, blast-radius-weighted net velocity" do
      imp_task(kind: "dead_code", files: 3)        # durable, blast 3
      imp_task(kind: "dead_code", reverted: true)  # -1

      board = described_class.improvement_scoreboard(account: account, window_days: 7)
      expect(board[:net_improvement_velocity]).to eq(2.0) # (3 capped) - 1, over 1 week
    end

    it "caps one kind's positive contribution so spamming cannot dominate" do
      30.times { imp_task(kind: "code_lint") } # weighted 30, capped to 20
      board = described_class.improvement_scoreboard(account: account, window_days: 7)
      expect(board[:net_improvement_velocity]).to eq(20.0)
    end

    it "ignores tasks with no improvement kind" do
      create(:ai_ralph_task, :passed, ralph_loop: loop_record, metadata: {})
      board = described_class.improvement_scoreboard(account: account)
      expect(board[:per_kind]).to be_empty
    end
  end

  describe "#blast_radius" do
    let(:loop_record) { create(:ai_ralph_loop, account: account) }

    it "floors at 1, caps at the max, and reads from metadata" do
      expect(create(:ai_ralph_task, ralph_loop: loop_record, metadata: { "blast_radius" => 0 }).blast_radius).to eq(1)
      expect(create(:ai_ralph_task, ralph_loop: loop_record, metadata: { "blast_radius" => 5 }).blast_radius).to eq(5)
      expect(create(:ai_ralph_task, ralph_loop: loop_record, metadata: { "blast_radius" => 999 }).blast_radius).to eq(10)
    end
  end

  # ==========================================================================
  # Operator resolution of a blocked task — a blocked task is "awaiting an
  # operator decision"; resolving it dispositions it to a terminal outcome
  # without the resume→reclaim→complete dance.
  # ==========================================================================
  describe "terminal transitions from blocked" do
    let(:blocked_task) { create(:ai_ralph_task, :blocked, ralph_loop: loop_record) }

    it "permits pass!/fail!/skip! from blocked" do
      expect(blocked_task.can_pass?).to be true
      expect(blocked_task.can_fail?).to be true
      expect(blocked_task.can_skip?).to be true
    end

    it "pass! from blocked → passed, clearing the block reason" do
      blocked_task.pass!(iteration_number: 7)
      blocked_task.reload
      expect(blocked_task.status).to eq("passed")
      expect(blocked_task.error_message).to be_nil
      expect(blocked_task.completed_in_iteration).to eq(7)
    end

    it "fail! from blocked → failed with the reason" do
      blocked_task.fail!(error_message: "abandoned")
      expect(blocked_task.reload.status).to eq("failed")
      expect(blocked_task.error_message).to eq("abandoned")
    end

    it "skip! from blocked → skipped" do
      blocked_task.skip!(reason: "superseded")
      expect(blocked_task.reload.status).to eq("skipped")
    end

    it "still rejects pass! from a terminal status" do
      passed = create(:ai_ralph_task, :passed, ralph_loop: loop_record)
      expect { passed.pass! }.to raise_error(Ai::RalphTask::InvalidTransitionError)
    end
  end

  # ==========================================================================
  # #review_parked? — "blocked" is overloaded between "unmet dependency" and
  # "parked for operator review" (scope-guardrail / human review). Only the
  # latter is review_parked?, and only that flavor must resist auto-unblock.
  # ==========================================================================
  describe "#review_parked?" do
    it "is false for a non-blocked task" do
      pending_task = create(:ai_ralph_task, :pending, ralph_loop: loop_record)
      expect(pending_task.review_parked?).to be false
    end

    it "is false for a dependency-blocked task (explicit blocked_for stamp)" do
      task = create(:ai_ralph_task, :blocked, ralph_loop: loop_record,
                    error_message: "Waiting for: task_1", metadata: { "blocked_for" => "dependency" })
      expect(task.review_parked?).to be false
    end

    it "is true for a review-parked task (explicit blocked_for stamp)" do
      task = create(:ai_ralph_task, :blocked, ralph_loop: loop_record,
                    error_message: "some reason", metadata: { "blocked_for" => "review" })
      expect(task.review_parked?).to be true
    end

    it "falls back to the scope-guardrail message marker for legacy rows with no blocked_for stamp" do
      task = create(:ai_ralph_task, :blocked, ralph_loop: loop_record,
                    error_message: "[scope-guardrail] touched payments/ — parked for human review")
      expect(task.review_parked?).to be true
    end

    it "falls back to the 'Awaiting human review' message marker for legacy rows with no blocked_for stamp" do
      task = create(:ai_ralph_task, :blocked, ralph_loop: loop_record, error_message: "Awaiting human review")
      expect(task.review_parked?).to be true
    end

    it "is false for a legacy dependency-block message with no blocked_for stamp" do
      task = create(:ai_ralph_task, :blocked, ralph_loop: loop_record, error_message: "Waiting for: task_1")
      expect(task.review_parked?).to be false
    end
  end

  # ==========================================================================
  # #unblock_dependent_tasks (invoked via pass!/skip!) — a review-parked
  # dependent task must NOT be swept back to pending just because its
  # dependency passed; only a dependency-blocked dependent should be.
  # ==========================================================================
  describe "#unblock_dependent_tasks" do
    let!(:upstream) { create(:ai_ralph_task, :in_progress, ralph_loop: loop_record, task_key: "up") }

    it "unblocks a dependency-blocked dependent task once the dependency passes" do
      dependent = create(:ai_ralph_task, :blocked, ralph_loop: loop_record, task_key: "down",
                         dependencies: ["up"], metadata: { "blocked_for" => "dependency" })
      upstream.pass!
      expect(dependent.reload.status).to eq("pending")
    end

    it "does NOT unblock a review-parked dependent task even though the dependency passes" do
      dependent = create(:ai_ralph_task, :blocked, ralph_loop: loop_record, task_key: "down",
                         dependencies: ["up"], metadata: { "blocked_for" => "review" },
                         error_message: "[scope-guardrail] touched auth/ — parked for human review")
      upstream.pass!
      expect(dependent.reload.status).to eq("blocked")
    end
  end

  # ==========================================================================
  # Staleness signal (read-only) — a claim sitting past the threshold with no
  # reported outcome is surfaced on the task, never auto-released.
  # ==========================================================================
  describe "#stale?" do
    before { stub_const("Ai::RalphTask::STALE_CLAIM_THRESHOLD", 5.minutes) }

    it "is true for an in_progress task claimed past the threshold" do
      task = create(:ai_ralph_task, :in_progress, ralph_loop: loop_record,
                     metadata: { "claimed_at" => 10.minutes.ago.iso8601 })

      expect(task.stale?).to be true
      expect(task.claimed_duration_seconds).to be_within(2).of(600)
    end

    it "is false for a freshly claimed in_progress task" do
      task = create(:ai_ralph_task, :in_progress, ralph_loop: loop_record,
                     metadata: { "claimed_at" => 1.minute.ago.iso8601 })

      expect(task.stale?).to be false
    end

    it "is false when the task has never been claimed" do
      task = create(:ai_ralph_task, :in_progress, ralph_loop: loop_record, metadata: {})

      expect(task.stale?).to be false
      expect(task.claimed_duration_seconds).to be_nil
    end

    it "is false for non in_progress tasks even with an old claimed_at" do
      task = create(:ai_ralph_task, :passed, ralph_loop: loop_record,
                     metadata: { "claimed_at" => 1.hour.ago.iso8601 })

      expect(task.stale?).to be false
    end

    it "is surfaced on task_details" do
      task = create(:ai_ralph_task, :in_progress, ralph_loop: loop_record,
                     metadata: { "claimed_at" => 10.minutes.ago.iso8601 })

      expect(task.task_details[:stale]).to be true
      expect(task.task_details[:claimed_duration_seconds]).to be_a(Integer)
    end
  end

  describe "#apply_operator_edit!" do
    let(:task) { create(:ai_ralph_task, ralph_loop: loop_record, acceptance_criteria: "original") }

    # The lock reloads, which would silently DISCARD a caller's pre-assignment
    # rather than raising as the old task-row with_lock did. Fail loudly instead
    # of losing the write.
    it "refuses a record with unpersisted changes" do
      task.acceptance_criteria = "assigned in memory"

      expect { task.apply_operator_edit!({ "description" => "x" }) }
        .to raise_error(ArgumentError, /clean record/)
    end

    # Lock choice is a DEADLOCK question. dev_complete_task takes the task row and
    # then reaches the loop row (via add_learning); an earlier version of this
    # method took loop-then-task, an AB/BA inversion. Same order as
    # complete_task = no cycle.
    it "locks the task row, matching dev_complete_task's order" do
      expect(task).to receive(:with_lock).and_call_original

      task.apply_operator_edit!({ "description" => "amended" })

      expect(task.reload.description).to eq("amended")
    end

    # The task lock does not serialize against the claim path (which writes under
    # the LOOP lock), so the metadata write must merge only our own keys rather
    # than rewriting the column.
    it "preserves concurrently-written claim keys instead of clobbering them" do
      task.update!(metadata: task.metadata.merge("claimed_by" => "user:99", "claimed_at" => "t0"))

      task.apply_operator_edit!({ "description" => "amended" }, note: "hi")

      meta = task.reload.metadata
      expect(meta["claimed_by"]).to eq("user:99")
      expect(meta["claimed_at"]).to eq("t0")
      expect(meta["operator_notes"].last["note"]).to eq("hi")
    end

    it "truncates a long note so the journal cannot grow the claim payload" do
      task.apply_operator_edit!({}, note: "y" * 5_000)

      stored = task.reload.metadata["operator_notes"].last["note"]
      expect(stored.bytesize).to be <= Ai::RalphTask::OPERATOR_JOURNAL_VALUE_LIMIT + 3
    end
  end
end
