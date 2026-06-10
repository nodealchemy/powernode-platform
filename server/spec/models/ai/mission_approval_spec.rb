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

    # Regression: the system_agent_fleet mission template defines a
    # gate_name override of "fleet_review". Before this gate was registered,
    # every approval attempt on an agent-fleet mission raised RecordInvalid,
    # leaving the entire launch_agent_fleet feature dead. See audit
    # 2026-06-09 finding F1-01.
    it "includes fleet_review (the agent-fleet template gate) in GATES" do
      expect(Ai::MissionApproval::GATES).to include("fleet_review")
    end
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
