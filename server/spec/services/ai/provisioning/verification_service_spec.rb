# frozen_string_literal: true

require "rails_helper"

# F2 (IMP 019fe4c4-c7c4): the verify phase blessed DB rows without consulting
# the live provider — `healthy=true` in 0.23s over a phantom instance whose VM
# never existed (dryrun 20260809a). Presence in the DB is never proof.
#
# VerificationService replaces the stub with real checks:
#   - the mission must reference a composed plan;
#   - every executed step must be completed, with NO recorded failures
#     (the rna step's failure WAS recorded in last_outputs and ignored);
#   - each provisioning step must have produced exactly the instances it was
#     asked for (count vs node_instance_ids);
#   - each produced instance is reconciled against the LIVE provider through
#     the `provision_verifier` extension seam (exists, has provider identity,
#     provider reports it running, region matches). Core mode (no seam) skips
#     live reconciliation but says so explicitly in the checks.
RSpec.describe Ai::Provisioning::VerificationService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, status: "active") }
  let(:goal) do
    Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Goal", goal_type: "creation",
      status: "pending", priority: 3, progress: 0.0, success_criteria: {}
    )
  end
  let(:plan) do
    Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                         status: "executing", version: 1, plan_data: {})
  end
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        configuration: { "plan" => { "plan_id" => plan.id } })
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  def provision_step!(number:, count:, region_id: "region-1", status: "completed",
                      instance_ids: [], failures: [])
    plan.steps.create!(
      step_number: number, step_type: "provisioning_skill", description: "provision",
      status: status,
      execution_config: { "skill" => "provision_full_stack", "on_failure" => "rollback",
                          "inputs" => { "count" => count, "provider_region_id" => region_id } },
      metadata: { "last_outputs" => { "count" => count,
                                      "outputs" => { "node_instance_ids" => instance_ids },
                                      "failures" => failures } }
    )
  end

  def stub_verifier(reconciler)
    allow(::Powernode::ExtensionRegistry).to receive(:provider).and_call_original
    allow(::Powernode::ExtensionRegistry).to receive(:provider)
      .with(:provision_verifier).and_return(reconciler)
  end

  context "with a live reconciler registered" do
    it "is healthy when steps completed cleanly and the provider confirms every instance" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      reconciler = double("verifier")
      expect(reconciler).to receive(:reconcile_instances) do |account:, expectations:|
        expect(account.id).to eq(mission.account_id)
        expect(expectations.map { |e| e[:node_instance_id] }).to match_array(%w[i-1 i-2])
        expect(expectations).to all(include(provider_region_id: "region-1"))
        expectations.map { |e| { node_instance_id: e[:node_instance_id], ok: true, detail: "provider reports running" } }
      end
      stub_verifier(reconciler)

      result = service.verify
      expect(result[:healthy]).to be true
      expect(result[:checks]).to all(include(ok: true))
    end

    it "is UNHEALTHY when the provider denies an instance (the phantom)" do
      provision_step!(number: 1, count: 1, instance_ids: %w[i-phantom])
      reconciler = double("verifier", reconcile_instances: [
                            { node_instance_id: "i-phantom", ok: false,
                              detail: "provider has no record of the instance" }
                          ])
      stub_verifier(reconciler)

      result = service.verify
      expect(result[:healthy]).to be false
      failing = result[:checks].reject { |c| c[:ok] }
      expect(failing.map { |c| c[:detail] }.join).to match(/no record/)
    end
  end

  context "step-level checks (no seam needed)" do
    before { stub_verifier(nil) }

    it "is UNHEALTHY when a step recorded failures — even though the step 'completed'" do
      # The rna step's exact shape: completed, partial, failure recorded and
      # previously ignored by everything downstream.
      provision_step!(number: 1, count: 1, instance_ids: [],
                      failures: [{ "step" => "provision_instance", "error" => "PVE error: 500 already exists" }])
      result = service.verify
      expect(result[:healthy]).to be false
      expect(result[:checks].reject { |c| c[:ok] }.map { |c| c[:detail] }.join).to match(/already exists|failure/i)
    end

    it "is UNHEALTHY when fewer instances were produced than requested" do
      provision_step!(number: 1, count: 3, instance_ids: %w[i-1 i-2])
      result = service.verify
      expect(result[:healthy]).to be false
      expect(result[:checks].reject { |c| c[:ok] }.map { |c| c[:detail] }.join).to match(%r{2/3})
    end

    it "is UNHEALTHY when a step is not completed" do
      provision_step!(number: 1, count: 1, status: "failed", instance_ids: [])
      expect(service.verify[:healthy]).to be false
    end

    it "is UNHEALTHY when the mission references no composed plan" do
      mission.update!(configuration: {})
      result = service.verify
      expect(result[:healthy]).to be false
      expect(result[:checks].map { |c| c[:detail] }.join).to match(/no composed plan/i)
    end
  end

  context "core mode (no provision_verifier registered)" do
    before { stub_verifier(nil) }

    it "stays healthy on clean steps but SAYS the instances were not live-verified" do
      provision_step!(number: 1, count: 1, instance_ids: %w[i-1])
      result = service.verify
      expect(result[:healthy]).to be true
      expect(result[:checks].map { |c| c[:detail] }.join).to match(/not live-verified|no provision_verifier/i)
    end
  end
end
