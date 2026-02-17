# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Mission, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name("User") }
    it { is_expected.to belong_to(:repository).class_name("Devops::GitRepository").optional }
    it { is_expected.to belong_to(:team).class_name("Ai::AgentTeam").optional }
    it { is_expected.to belong_to(:conversation).class_name("Ai::Conversation").optional }
    it { is_expected.to have_many(:approvals).class_name("Ai::MissionApproval") }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:mission_type) }
    it { is_expected.to validate_inclusion_of(:mission_type).in_array(Ai::Mission::MISSION_TYPES) }
    it { is_expected.to validate_inclusion_of(:status).in_array(Ai::Mission::STATUSES) }
  end

  describe "repository validation for development type" do
    it "requires repository for development missions" do
      mission = build(:ai_mission, mission_type: "development")
      mission.repository = nil
      expect(mission).not_to be_valid
      expect(mission.errors[:repository]).to include("is required for development missions")
    end

    it "does not require repository for research missions" do
      mission = build(:ai_mission, :research)
      expect(mission).to be_valid
    end
  end

  describe "#phases_for_type" do
    it "returns development phases for development type" do
      mission = build(:ai_mission, :development)
      expect(mission.phases_for_type).to eq(Ai::Mission::DEVELOPMENT_PHASES)
    end

    it "returns research phases for research type" do
      mission = build(:ai_mission, :research)
      expect(mission.phases_for_type).to eq(Ai::Mission::RESEARCH_PHASES)
    end

    it "returns operations phases for operations type" do
      mission = build(:ai_mission, :operations)
      expect(mission.phases_for_type).to eq(Ai::Mission::OPERATIONS_PHASES)
    end
  end

  describe "#terminal?" do
    it "returns true for completed missions" do
      mission = build(:ai_mission, status: "completed")
      expect(mission.terminal?).to be true
    end

    it "returns false for active missions" do
      mission = build(:ai_mission, status: "active")
      expect(mission.terminal?).to be false
    end
  end

  describe "#awaiting_approval?" do
    it "returns true when in approval gate phase" do
      mission = build(:ai_mission, current_phase: "awaiting_feature_approval")
      expect(mission.awaiting_approval?).to be true
    end

    it "returns false when in non-approval phase" do
      mission = build(:ai_mission, current_phase: "analyzing")
      expect(mission.awaiting_approval?).to be false
    end
  end

  describe "#phase_progress" do
    it "returns 0 for first phase" do
      mission = build(:ai_mission, :development, current_phase: "analyzing")
      expect(mission.phase_progress).to eq(0)
    end

    it "returns 100 for completed phase" do
      mission = build(:ai_mission, :development, current_phase: "completed")
      expect(mission.phase_progress).to eq(100)
    end
  end

  describe "scopes" do
    let!(:active_mission) { create(:ai_mission, :active) }
    let!(:completed_mission) { create(:ai_mission, :completed) }
    let!(:draft_mission) { create(:ai_mission) }

    it "filters active missions" do
      expect(Ai::Mission.active).to include(active_mission)
      expect(Ai::Mission.active).not_to include(completed_mission)
    end

    it "filters completed missions" do
      expect(Ai::Mission.completed).to include(completed_mission)
      expect(Ai::Mission.completed).not_to include(active_mission)
    end

    it "filters draft missions" do
      expect(Ai::Mission.draft).to include(draft_mission)
    end
  end
end
