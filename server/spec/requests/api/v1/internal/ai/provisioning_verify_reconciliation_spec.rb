# frozen_string_literal: true

require "rails_helper"

# F2 (IMP 019fe4c4-c7c4) — the INTERNAL verify endpoint must fail the phase
# when verification fails, not advance regardless. Observed live (dryrun
# 20260809a): the stub marked healthy=true in 0.23s over a phantom instance
# and advanced to handoff; an auto-approving harness (P2) would have handed
# off a broken stack as healthy.
RSpec.describe "Internal AI provisioning verify reconciliation", type: :request do
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
                         status: "executing", version: 1, plan_data: {})
  end

  let(:mission) do
    create(
      :ai_mission,
      account: mission_account,
      created_by: mission_user,
      mission_type: "infrastructure",
      status: "active",
      current_phase: "verify",
      custom_phases: [
        { "key" => "verify", "label" => "Verify", "order" => 0 },
        { "key" => "handoff", "label" => "Handoff", "order" => 1 }
      ],
      configuration: { "plan" => { "plan_id" => plan.id } }
    )
  end

  def add_step!(instance_ids:, failures: [], count: nil)
    plan.steps.create!(
      step_number: 1, step_type: "provisioning_skill", description: "provision",
      status: "completed",
      execution_config: { "skill" => "provision_full_stack", "on_failure" => "rollback",
                          "inputs" => { "count" => count || instance_ids.size, "provider_region_id" => "r-1" } },
      metadata: { "last_outputs" => { "outputs" => { "node_instance_ids" => instance_ids },
                                      "failures" => failures } }
    )
  end

  def stub_verifier(results_by_id)
    allow(::Powernode::ExtensionRegistry).to receive(:provider).and_call_original
    verifier = double("verifier")
    allow(verifier).to receive(:reconcile_instances) do |expectations:, **|
      expectations.map do |e|
        { node_instance_id: e[:node_instance_id] }.merge(results_by_id.fetch(e[:node_instance_id]))
      end
    end
    allow(::Powernode::ExtensionRegistry).to receive(:provider)
      .with(:provision_verifier).and_return(verifier)
  end

  it "advances past verify when the provider confirms every instance" do
    add_step!(instance_ids: %w[i-1])
    stub_verifier("i-1" => { ok: true, detail: "provider reports running" })

    post "/api/v1/internal/ai/provisioning/missions/#{mission.id}/verify",
         headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.dig("data", "healthy")).to be true
    expect(mission.reload.current_phase).to eq("handoff")
  end

  it "does NOT advance — and records why — when verification fails" do
    add_step!(instance_ids: %w[i-phantom])
    stub_verifier("i-phantom" => { ok: false, detail: "provider has no record of the instance" })

    post "/api/v1/internal/ai/provisioning/missions/#{mission.id}/verify",
         headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.dig("data", "healthy")).to be false

    mission.reload
    expect(mission.current_phase).to eq("verify")
    expect(mission.error_message.to_s).to match(/verif/i)
    verification = mission.configuration["verification"]
    expect(verification["healthy"]).to be false
    expect(verification["checks"]).to be_an(Array)
    expect(verification["checks"].reject { |c| c["ok"] }).not_to be_empty
  end
end
