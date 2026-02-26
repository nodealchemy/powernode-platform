# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Missions::OrchestratorService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) { create(:ai_mission, account: account, created_by: user) }
  let(:service) { described_class.new(mission: mission) }

  before do
    allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
  end

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

  describe "#advance!" do
    before { mission.update!(status: "active", current_phase: "analyzing") }

    it "moves to the next phase" do
      service.advance!
      expect(mission.reload.current_phase).to eq("awaiting_feature_approval")
    end

    it "rejects stale advances" do
      service.advance!(expected_phase: "executing")
      expect(mission.reload.current_phase).to eq("analyzing")
    end
  end

  describe "dynamic job resolution" do
    it "resolves job class from template" do
      job = service.send(:job_class_for_phase, "analyzing")
      expect(job).to eq("AiMissionAnalyzeJob")
    end

    it "returns nil for approval gate phases" do
      job = service.send(:job_class_for_phase, "awaiting_feature_approval")
      expect(job).to be_nil
    end
  end

  describe "dynamic rejection mapping" do
    it "resolves rejection target from template" do
      target = service.send(:resolve_rejection_target, "awaiting_feature_approval")
      expect(target).to eq("analyzing")
    end

    it "resolves prd rejection target" do
      target = service.send(:resolve_rejection_target, "awaiting_prd_approval")
      expect(target).to eq("planning")
    end
  end
end
