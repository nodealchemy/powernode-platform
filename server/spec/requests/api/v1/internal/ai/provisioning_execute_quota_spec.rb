# frozen_string_literal: true

require "rails_helper"

# Coverage for the QUOTA GATE on the internal execute endpoint.
#
# The bridge fails CLOSED when the billing handler errors, which means a denial
# now arrives for two very different reasons, and the endpoint must not conflate
# them:
#
#   * a real plan verdict      -> 200 + upgrade payload (terminal, renderable)
#   * a DEGRADED check failure -> 422 + error (the check itself broke)
#
# The distinction is load-bearing, not cosmetic. AiProvisioningExecuteJob
# (worker/app/jobs/ai_provisioning_execute_job.rb) only calls report_failure on
# `success: false`. A 200 for the degraded case leaves the mission un-advanced,
# un-failed and unretried, with nothing but a green "kicked off" log line
# carrying a nil runner_id — the failure mode is invisible.
RSpec.describe "Internal AI provisioning execute quota gate", type: :request do
  include_context "internal api auth"

  let(:mission_account) { create(:account) }
  let(:mission_user) { create(:user, account: mission_account) }
  let(:agent) { create(:ai_agent, account: mission_account, creator: mission_user, status: "active") }
  let(:goal) do
    Ai::AgentGoal.create!(
      account: mission_account, agent: agent, title: "Goal", goal_type: "creation",
      status: "pending", priority: 3, progress: 0.0, success_criteria: {}
    )
  end
  let(:plan) do
    Ai::GoalPlan.create!(account: mission_account, goal: goal, agent: agent,
                         status: "draft", version: 1, plan_data: {})
  end

  let(:mission) do
    create(
      :ai_mission,
      account: mission_account,
      created_by: mission_user,
      mission_type: "infrastructure",
      custom_phases: [{ "key" => "execute", "label" => "Execute", "order" => 0 }],
      configuration: { "plan" => { "plan_id" => plan.id } }
    )
  end

  def post_execute
    post "/api/v1/internal/ai/provisioning/missions/#{mission.id}/execute",
         headers: service_headers
  end

  around do |example|
    original = Powernode::BillingBridge.provisioning_quota_handler
    example.run
  ensure
    Powernode::BillingBridge.provisioning_quota_handler = original
  end

  context "when the quota handler denies with a real plan verdict" do
    before do
      Powernode::BillingBridge.provisioning_quota_handler = lambda do |account:, mission:|
        {
          allowed: false,
          payload: { reason: "no_subscription", cap: nil, upgrade_url: "/checkout" }
        }
      end
    end

    it "returns 200 with the canonical upgrade payload so the caller renders a card" do
      expect(::Ai::Provisioning::SkillCompositionRunner).not_to receive(:new)

      post_execute

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
      expect(body["data"]["reason"]).to eq("no_subscription")
      expect(body["data"]["requires_upgrade"]).to be true
      expect(body["data"]["mission_id"]).to eq(mission.id)
    end

    it "leaves the mission's error_message untouched — this is a verdict, not a fault" do
      post_execute

      expect(mission.reload.error_message).to be_nil
    end
  end

  context "when the quota handler itself fails (bridge fails CLOSED)" do
    before do
      Powernode::BillingBridge.provisioning_quota_handler = lambda do |account:, mission:|
        raise StandardError, "billing backend unreachable"
      end
    end

    it "does NOT provision" do
      expect(::Ai::Provisioning::SkillCompositionRunner).not_to receive(:new)

      post_execute
    end

    it "reports failure rather than success, so the worker marks the mission failed" do
      post_execute

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["success"]).to be false
    end

    it "records the reason on the mission instead of stranding it silently" do
      post_execute

      expect(mission.reload.error_message).to include("quota could not be checked")
    end

    it "carries the degraded reason in the error details" do
      post_execute

      details = JSON.parse(response.body)["details"]
      expect(details["reason"]).to eq(Powernode::BillingBridge::DEGRADED_QUOTA_REASON)
      expect(details["requires_upgrade"]).to be true
      expect(details["mission_id"]).to eq(mission.id)
    end
  end

  context "when the quota handler allows" do
    before do
      Powernode::BillingBridge.provisioning_quota_handler = ->(account:, mission:) { { allowed: true } }
    end

    it "proceeds to the runner" do
      runner = instance_double(::Ai::Provisioning::SkillCompositionRunner)
      expect(::Ai::Provisioning::SkillCompositionRunner).to receive(:new).and_return(runner)
      expect(runner).to receive(:execute!).and_return({ runner_id: "r-1", step_count: 2 })

      post_execute

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
    end
  end
end
