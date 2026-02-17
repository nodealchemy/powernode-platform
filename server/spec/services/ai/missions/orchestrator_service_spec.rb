# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Missions::OrchestratorService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) { create(:ai_mission, account: account, created_by: user) }
  let(:service) { described_class.new(mission: mission) }

  describe "#start!" do
    it "activates the mission" do
      service.start!
      expect(mission.reload.status).to eq("active")
      expect(mission.current_phase).to eq("analyzing")
      expect(mission.started_at).to be_present
    end

    it "raises error if not in draft status" do
      mission.update!(status: "active", current_phase: "analyzing")
      expect { service.start! }.to raise_error(described_class::OrchestrationError)
    end
  end

  describe "#cancel!" do
    before { mission.update!(status: "active", current_phase: "analyzing") }

    it "cancels the mission" do
      service.cancel!(reason: "No longer needed")
      expect(mission.reload.status).to eq("cancelled")
      expect(mission.error_message).to eq("No longer needed")
    end
  end

  describe "#pause!" do
    before { mission.update!(status: "active", current_phase: "analyzing") }

    it "pauses the mission" do
      service.pause!
      expect(mission.reload.status).to eq("paused")
    end

    it "raises error if not active" do
      mission.update!(status: "draft", current_phase: nil)
      expect { service.pause! }.to raise_error(described_class::OrchestrationError)
    end
  end

  describe "#resume!" do
    before { mission.update!(status: "paused", current_phase: "analyzing") }

    it "resumes the mission" do
      service.resume!
      expect(mission.reload.status).to eq("active")
    end
  end

  describe "#handle_approval!" do
    before { mission.update!(status: "active", current_phase: "awaiting_feature_approval") }

    it "creates an approval record on approve" do
      expect {
        service.handle_approval!(
          gate: "awaiting_feature_approval",
          user: user,
          decision: "approved",
          selected_feature: { title: "Test Feature" }
        )
      }.to change(Ai::MissionApproval, :count).by(1)
    end

    it "stores selected feature on approve" do
      service.handle_approval!(
        gate: "awaiting_feature_approval",
        user: user,
        decision: "approved",
        selected_feature: { title: "Test Feature", description: "A test" }
      )
      expect(mission.reload.selected_feature).to include("title" => "Test Feature")
    end
  end
end
