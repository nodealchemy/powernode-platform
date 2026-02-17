# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::MissionApproval, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:mission).class_name("Ai::Mission") }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:gate) }
    it { is_expected.to validate_presence_of(:decision) }
    it { is_expected.to validate_inclusion_of(:gate).in_array(Ai::MissionApproval::GATES) }
    it { is_expected.to validate_inclusion_of(:decision).in_array(Ai::MissionApproval::DECISIONS) }
  end

  describe "#approved?" do
    it "returns true when decision is approved" do
      approval = build(:ai_mission_approval, decision: "approved")
      expect(approval.approved?).to be true
    end
  end

  describe "#rejected?" do
    it "returns true when decision is rejected" do
      approval = build(:ai_mission_approval, :rejected)
      expect(approval.rejected?).to be true
    end
  end
end
