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

  # IMP-8c37b9e5ccd5 (INC-2): an adaptation is APPENDED onto this same live
  # plan, so the post-adapt re-run walks its steps too. A `scale_project` step
  # declares the instances it asks for as `target_count` (the delta of new
  # instances), not `count` — reading only `count` scored every adaptation
  # "provisioned 2/0 instances" and failed a mission whose scale-out had
  # succeeded.
  context "with an appended adaptation step" do
    def adaptation_step!(number:, target_count:, instance_ids:, region_id: "region-1")
      plan.steps.create!(
        step_number: number, step_type: "provisioning_skill", description: "Scale project",
        status: "completed",
        execution_config: { "skill" => "scale_project", "on_failure" => "rollback",
                            "adapted_from_plan_id" => SecureRandom.uuid,
                            "inputs" => { "target_count" => target_count,
                                          "scaling_strategy" => "add_replicas",
                                          "provider_region_id" => region_id } },
        metadata: { "last_outputs" => { "outputs" => { "node_instance_ids" => instance_ids },
                                        "failures" => [] } }
      )
    end

    it "counts the adaptation step against its declared target_count" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      adaptation_step!(number: 2, target_count: 2, instance_ids: %w[i-3 i-4])
      stub_verifier(nil)

      result = service.verify

      count_check = result[:checks].find { |c| c[:name] == "step_2_count" }
      expect(count_check[:ok]).to be true
      expect(count_check[:detail]).to eq("provisioned 2/2 instances")
      expect(result[:healthy]).to be true
    end

    it "still fails an adaptation step that produced fewer instances than it asked for" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      adaptation_step!(number: 2, target_count: 2, instance_ids: %w[i-3])
      stub_verifier(nil)

      result = service.verify

      expect(result[:checks].find { |c| c[:name] == "step_2_count" }[:ok]).to be false
      expect(result[:healthy]).to be false
    end

    it "does NOT read target_count for a non-additive scaling step" do
      # A vertical resize / rolling upgrade takes a target_count but creates no
      # instances and returns an empty node_instance_ids. An unscoped fallback
      # expected N, saw 0, and failed that step — and so the mission —
      # permanently, with nothing an operator could do about it.
      provision_step!(number: 1, count: 1, instance_ids: %w[i-1])
      plan.steps.create!(
        step_number: 2, step_type: "provisioning_skill", description: "Resize", status: "completed",
        execution_config: { "skill" => "scale_project", "on_failure" => "rollback",
                            "adapted_from_plan_id" => SecureRandom.uuid,
                            "inputs" => { "target_count" => 3,
                                          "scaling_strategy" => "vertical_resize" } },
        metadata: { "last_outputs" => { "outputs" => { "node_instance_ids" => [] },
                                        "failures" => [] } }
      )
      stub_verifier(nil)

      result = service.verify

      expect(result[:checks].map { |c| c[:name] }).not_to include("step_2_count")
      expect(result[:healthy]).to be true
    end

    it "reconciles the adaptation's new instances against the live provider too" do
      provision_step!(number: 1, count: 1, instance_ids: %w[i-1])
      adaptation_step!(number: 2, target_count: 1, instance_ids: %w[i-3], region_id: "region-9")
      reconciler = double("verifier")
      seen = nil
      allow(reconciler).to receive(:reconcile_instances) do |account:, expectations:|
        seen = expectations
        expectations.map { |e| { node_instance_id: e[:node_instance_id], ok: true, detail: "running" } }
      end
      stub_verifier(reconciler)

      service.verify

      expect(seen.map { |e| e[:node_instance_id] }).to match_array(%w[i-1 i-3])
      expect(seen.find { |e| e[:node_instance_id] == "i-3" }[:provider_region_id]).to eq("region-9")
    end
  end

  # INC-4 (IMP-216a6dbc7e32): the scale-IN strategy. A removal creates
  # nothing, so grading it with the instance-creation oracle fails
  # `step_N_count` permanently — the mission then verifies unhealthy forever
  # and, because the adaptation lane settles on verification, EVERY later
  # adaptation on that mission can never settle. One removal would poison the
  # mission's whole evolution loop. A removal's success is that the victims
  # are GONE, with their peers and volumes — the executor's post-teardown
  # ground-truth sweep, recorded as `outputs.orphans`.
  context "with an appended removal step" do
    def removal_step!(number:, orphans: [], removed: %w[i-1], status: "completed", failures: [],
                      outputs: nil, target_count: 1, floor_reached: false)
      plan.steps.create!(
        step_number: number, step_type: "provisioning_skill", description: "Remove replicas",
        status: status,
        execution_config: { "skill" => "scale_project", "on_failure" => "rollback",
                            "adapted_from_plan_id" => SecureRandom.uuid,
                            "inputs" => { "target_count" => target_count,
                                          "scaling_strategy" => "remove_replicas" } },
        metadata: { "last_outputs" => {
          "outputs" => outputs || { "node_instance_ids" => [],
                                    "removed_node_instance_ids" => removed,
                                    "detached_sdwan_peer_ids" => %w[p-1],
                                    "deleted_storage_volume_ids" => %w[v-1],
                                    "prefix_enforced" => "dryrun-evo-01",
                                    "floor_reached" => floor_reached,
                                    "orphans" => orphans },
          "failures" => failures
        } }
      )
    end

    it "verifies HEALTHY after a removal and never grades it by an instance count" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      removal_step!(number: 2)
      stub_verifier(nil)

      result = service.verify

      expect(result[:checks].map { |c| c[:name] }).not_to include("step_2_count")
      removal_check = result[:checks].find { |c| c[:name] == "step_2_removal" }
      expect(removal_check[:ok]).to be true
      expect(result[:healthy]).to be true
    end

    it "is UNHEALTHY when the removal's own sweep recorded an orphan" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      removal_step!(number: 2,
                    orphans: [ { "resource" => "sdwan_peer", "ids" => %w[p-9] } ],
                    failures: [ { "step" => "remove_replicas", "error" => "orphaned resources" } ])
      stub_verifier(nil)

      result = service.verify

      expect(result[:checks].find { |c| c[:name] == "step_2_removal" }[:ok]).to be false
      expect(result[:healthy]).to be false
    end

    it "grades a removal whose outputs carry NO orphan sweep as unverifiable" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      # Absence of evidence is not a clean sweep. Array(nil) is empty, so a
      # step whose outputs never carried the key would otherwise read exactly
      # like one that swept and found nothing — the opposite of the
      # fail-closed rule #reconcile already applies to a silent reconciler.
      removal_step!(number: 2, outputs: { "node_instance_ids" => [],
                                          "removed_node_instance_ids" => %w[i-2] })
      stub_verifier(nil)

      result = service.verify

      check = result[:checks].find { |c| c[:name] == "step_2_removal" }
      expect(check[:ok]).to be false
      expect(check[:detail]).to match(/no orphan sweep|unverifiable/i)
      expect(result[:healthy]).to be false
    end

    it "fails a removal that removed nothing while not at the floor" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      removal_step!(number: 2, target_count: 1, removed: [], floor_reached: false)
      stub_verifier(nil)

      result = service.verify

      expect(result[:checks].find { |c| c[:name] == "step_2_removal" }[:ok]).to be false
      expect(result[:healthy]).to be false
    end

    it "passes a floor no-op, and says the floor is why nothing went" do
      provision_step!(number: 1, count: 1, instance_ids: %w[i-1])
      removal_step!(number: 2, target_count: 1, removed: [], floor_reached: true)
      stub_verifier(nil)

      result = service.verify

      check = result[:checks].find { |c| c[:name] == "step_2_removal" }
      expect(check[:ok]).to be true
      expect(check[:detail]).to match(/floor/i)
      expect(result[:healthy]).to be true
    end

    it "says WHICH containment rail was measured, so a nil prefix is not read as clean" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      removal_step!(number: 2, outputs: { "node_instance_ids" => [],
                                          "removed_node_instance_ids" => %w[i-2],
                                          "prefix_enforced" => nil,
                                          "orphans" => [] })
      stub_verifier(nil)

      detail = service.verify[:checks].find { |c| c[:name] == "step_2_removal" }[:detail]
      expect(detail).to match(/prefix/i)
    end

    # The victim's absence has to be verified against the PROVIDER for the
    # same reason its presence did (F2). Taking the executor's word that a
    # victim is gone inverts the phantom: a row marked terminated over a guest
    # the hypervisor still runs is invisible to the platform and bills forever.
    it "reconciles removed victims as EXPECTED-ABSENT against the live provider" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      removal_step!(number: 2, removed: %w[i-2])
      reconciler = double("verifier")
      absent_seen = nil
      allow(reconciler).to receive(:reconcile_instances) do |account:, expectations:|
        expectations.map { |e| { node_instance_id: e[:node_instance_id], ok: true, detail: "running" } }
      end
      allow(reconciler).to receive(:reconcile_absent_instances) do |account:, expectations:|
        absent_seen = expectations
        expectations.map { |e| { node_instance_id: e[:node_instance_id], ok: true, detail: "gone" } }
      end
      stub_verifier(reconciler)

      result = service.verify

      expect(absent_seen.map { |e| e[:node_instance_id] }).to eq(%w[i-2])
      expect(result[:healthy]).to be true
    end

    it "is UNHEALTHY when the provider still runs a victim the platform called terminated" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      removal_step!(number: 2, removed: %w[i-2])
      reconciler = double("verifier")
      allow(reconciler).to receive(:reconcile_instances) do |account:, expectations:|
        expectations.map { |e| { node_instance_id: e[:node_instance_id], ok: true, detail: "running" } }
      end
      allow(reconciler).to receive(:reconcile_absent_instances)
        .and_return([ { node_instance_id: "i-2", ok: false, detail: "provider still reports running" } ])
      stub_verifier(reconciler)

      result = service.verify

      expect(result[:healthy]).to be false
      expect(result[:checks].map { |c| c[:detail] }.join).to match(/still reports running/)
    end

    it "annotates rather than blesses when the verifier cannot check absence" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      removal_step!(number: 2, removed: %w[i-2])
      # An older verifier answers presence but not absence. Core mode already
      # treats "cannot be asked" as healthy-but-annotated; the same reading
      # applies here, and the check has to SAY it was not live-verified.
      reconciler = double("verifier")
      allow(reconciler).to receive(:reconcile_instances).and_return([])
      stub_verifier(reconciler)

      result = service.verify

      expect(result[:healthy]).to be true
      expect(result[:checks].map { |c| c[:detail] }.join).to match(/not live-verified/i)
    end

    # The deeper half of the trap: the victim was recorded by the step that
    # CREATED it, and that step's expectations are what reach the live
    # reconciler. Left in, a successful removal makes the reconciler report a
    # terminated instance as not-running — so the mission verifies unhealthy
    # forever, from the creating step rather than the removing one.
    it "drops a removed victim from the CREATING step's live expectations" do
      provision_step!(number: 1, count: 2, instance_ids: %w[i-1 i-2])
      removal_step!(number: 2, removed: %w[i-2])
      reconciler = double("verifier")
      seen = nil
      allow(reconciler).to receive(:reconcile_instances) do |account:, expectations:|
        seen = expectations
        expectations.map { |e| { node_instance_id: e[:node_instance_id], ok: true, detail: "running" } }
      end
      stub_verifier(reconciler)

      result = service.verify

      expect(seen.map { |e| e[:node_instance_id] }).to eq(%w[i-1])
      expect(result[:healthy]).to be true
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
