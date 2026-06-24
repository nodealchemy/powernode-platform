# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::RalphIteration, type: :model do
  let(:account) { create(:account) }
  let(:loop_record) { create(:ai_ralph_loop, account: account) }

  describe "#can_skip? / #skip!" do
    it "is true from pending and from running" do
      expect(create(:ai_ralph_iteration, ralph_loop: loop_record).can_skip?).to be true
      expect(create(:ai_ralph_iteration, :running, ralph_loop: loop_record).can_skip?).to be true
    end

    it "skips a running iteration (operator disposition recorded, then skipped)" do
      iteration = create(:ai_ralph_iteration, :running, ralph_loop: loop_record)
      iteration.skip!(reason: "superseded")
      expect(iteration.reload.status).to eq("skipped")
    end

    it "is false once terminal" do
      expect(create(:ai_ralph_iteration, :completed, ralph_loop: loop_record).can_skip?).to be false
    end
  end
end
