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
end
