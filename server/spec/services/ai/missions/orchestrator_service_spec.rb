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

  describe "#handle_approval! second-signature gate" do
    let(:user_a) { create(:user, account: account) }
    let(:user_b) { create(:user, account: account) }
    let(:second_sig_mission) do
      create(:ai_mission,
             account: account,
             created_by: user_a,
             mission_type: "custom",
             repository: nil,
             mission_template: nil,
             custom_phases: [
               { "key" => "handoff", "label" => "Handoff", "order" => 0, "requires_approval" => true, "gate_name" => "handoff" },
               { "key" => "adapting", "label" => "Adapting", "order" => 1, "requires_approval" => false }
             ])
    end
    let(:second_sig_service) { described_class.new(mission: second_sig_mission) }

    before do
      second_sig_mission.update!(status: "active", current_phase: "handoff")
    end

    def stub_plan(features_hash)
      plan = double("Plan", features: features_hash)
      sub  = double("Subscription", plan: plan)
      allow(account).to receive(:active_subscription).and_return(sub)
      # Re-bind the orchestrator's lazy account memoization to our stubbed
      # account so the predicate sees the stubbed chain.
      allow(second_sig_mission).to receive(:account).and_return(account)
    end

    context "Pro tier (single approval flow preserved)" do
      it "advances on a single approver when second_signature_required is false" do
        stub_plan("second_signature_required" => false)

        second_sig_service.handle_approval!(
          gate: "handoff",
          user: user_a,
          decision: "approved"
        )

        expect(second_sig_mission.reload.current_phase).to eq("adapting")
      end

      it "advances when the feature flag is missing entirely (legacy plans)" do
        stub_plan({})

        second_sig_service.handle_approval!(
          gate: "handoff",
          user: user_a,
          decision: "approved"
        )

        expect(second_sig_mission.reload.current_phase).to eq("adapting")
      end
    end

    context "Business+ tier (second-signature required)" do
      before { stub_plan("second_signature_required" => true) }

      it "stays at handoff after the first approval" do
        expect {
          second_sig_service.handle_approval!(
            gate: "handoff",
            user: user_a,
            decision: "approved"
          )
        }.to change(Ai::MissionApproval, :count).by(1)

        expect(second_sig_mission.reload.current_phase).to eq("handoff")
      end

      it "stays at handoff when the same user approves twice" do
        second_sig_service.handle_approval!(gate: "handoff", user: user_a, decision: "approved")
        second_sig_service.handle_approval!(gate: "handoff", user: user_a, decision: "approved")

        expect(second_sig_mission.reload.current_phase).to eq("handoff")
        expect(second_sig_mission.approvals.approved.where(gate: "handoff").count).to eq(2)
      end

      it "advances when a second distinct user approves" do
        second_sig_service.handle_approval!(gate: "handoff", user: user_a, decision: "approved")
        second_sig_service.handle_approval!(gate: "handoff", user: user_b, decision: "approved")

        expect(second_sig_mission.reload.current_phase).to eq("adapting")
      end

      it "records both approvers in the audit trail" do
        second_sig_service.handle_approval!(gate: "handoff", user: user_a, decision: "approved", comment: "first")
        second_sig_service.handle_approval!(gate: "handoff", user: user_b, decision: "approved", comment: "second")

        approver_ids = second_sig_mission.approvals.approved.where(gate: "handoff").pluck(:user_id)
        expect(approver_ids).to contain_exactly(user_a.id, user_b.id)
      end

      it "rejects with a single rejection (does not require two)" do
        second_sig_service.handle_approval!(
          gate: "handoff",
          user: user_a,
          decision: "rejected",
          comment: "veto"
        )

        # No rejection_mapping configured for custom_phases, so the mission
        # just records the rejection and stays at handoff (rejection_target nil).
        expect(second_sig_mission.reload.current_phase).to eq("handoff")
        expect(second_sig_mission.approvals.rejected.count).to eq(1)
      end
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
