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

  describe "#add_learning" do
    it "appends a structured learning entry" do
      loop_record.add_learning("Discovered a flaky spec", context: { task_key: "IMP-1" })
      entry = loop_record.reload.learnings.last

      expect(entry["text"]).to eq("Discovered a flaky spec")
      expect(entry["context"]).to eq({ "task_key" => "IMP-1" })
      expect(entry["iteration"]).to eq(loop_record.current_iteration)
    end

    it "preserves prior learnings across successive appends" do
      loop_record.add_learning("first")
      loop_record.add_learning("second")
      texts = loop_record.reload.learnings.map { |l| l["text"] }
      expect(texts).to eq(%w[first second])
    end

    it "appends under a row lock" do
      expect(loop_record).to receive(:with_lock).and_call_original
      loop_record.add_learning("locked append")
    end
  end
end
