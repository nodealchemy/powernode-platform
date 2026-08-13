# frozen_string_literal: true

require "rails_helper"

# IMP-051509357291 — the approval card quoted resources the plan never
# provisions.
#
# CostEstimatorService read the per-step volume size as
# `inputs["storage_gb"] || DEFAULT_STORAGE_GB_PER_INSTANCE` and the egress
# allowance as `inputs["egress_gb"] || DEFAULT_EGRESS_GB_PER_INSTANCE`.
# Neither key is written by anything: PlanComposerService#merge_resolved_inputs!
# stamps `with_storage_gb` (the kwarg ProvisionFullStackExecutor consumes) and
# nothing anywhere writes `egress_gb`. Both `||` chains therefore always reached
# their defaults, so every provisioning approval card billed a phantom 50GB
# volume + 100GB egress PER INSTANCE for resources the plan does not provision.
#
# The rule these examples pin is NO DATA ⇒ NO LINE: a cost line appears only
# when the step actually declares the resource. The confidence knock-on is
# deliberate and pinned below — an unpinned step stops being "priced" by its own
# phantom lines, so confidence falls to "low" rather than reporting "high"
# confidence in a fabricated number.
#
# Placement: this file stays free of extension constants (core-purity gate #9).
# The examples that need a real priced instance type live in the companion
# `cost_estimator_service_spec.rb`, which is baselined for that reference.
RSpec.describe Ai::Provisioning::CostEstimatorService, "phantom cost lines", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  subject(:service) { described_class.new(account: account) }

  let(:default_brief) do
    {
      "intent" => "Provision a 3-node cluster",
      "use_case" => "OLTP",
      "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
      "regions" => ["us-east-1"],
      "compliance" => [],
      "budget_cap_usd_monthly" => 500.0
    }
  end

  def build_plan(steps:, brief: default_brief)
    mission = create(
      :ai_mission,
      account: account, created_by: user, mission_type: "infrastructure",
      custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
      configuration: { "brief" => brief }
    )
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent,
      title: "Provisioning goal", description: "test",
      goal_type: "creation", status: "pending", priority: 3, progress: 0.0,
      success_criteria: { "mission_id" => mission.id },
      metadata: { "provisioning_mission_id" => mission.id }
    )
    plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "draft", version: 1)
    steps.each_with_index do |cfg, idx|
      Ai::GoalPlanStep.create!(
        plan: plan, step_number: idx + 1, step_type: "provisioning_skill",
        status: "pending", execution_config: cfg, dependencies: []
      )
    end
    plan
  end

  def rows_of(result, type)
    result[:by_resource].select { |r| r[:resource_type] == type }
  end

  # ---- (a) storage: no volume requested ⇒ no volume line ---------------------

  describe "storage lines" do
    it "emits NO storage line when the step declares no volume" do
      plan = build_plan(steps: [
        { "skill" => "provision_full_stack", "inputs" => { "count" => 3 } }
      ])

      expect(rows_of(service.estimate(plan: plan), "storage")).to be_empty
    end

    it "prices the volume the executor will actually provision, from with_storage_gb" do
      plan = build_plan(steps: [
        { "skill" => "provision_full_stack", "inputs" => { "count" => 2, "with_storage_gb" => 250 } }
      ])

      storage = rows_of(service.estimate(plan: plan), "storage")
      expect(storage.size).to eq(1)
      expect(storage.first[:count]).to eq(2)
      # 250GB × 2 instances × $0.10/GB-month
      expect(storage.first[:monthly_usd]).to eq(50.0)
      expect(storage.first[:name]).to include("250GB volume")
    end

    it "treats an explicitly nil volume size as no volume, not as the default" do
      # The TRAP recorded on this task: renaming the key without removing the
      # default would be a no-op. The default is the defect, not the key name.
      plan = build_plan(steps: [
        { "skill" => "provision_full_stack",
          "inputs" => { "count" => 3, "with_storage_gb" => nil, "egress_gb" => nil } }
      ])

      result = service.estimate(plan: plan)
      expect(rows_of(result, "storage")).to be_empty
      expect(rows_of(result, "network")).to be_empty
    end

    it "ignores a non-positive volume size the way the executor does" do
      plan = build_plan(steps: [
        { "skill" => "provision_full_stack", "inputs" => { "count" => 2, "with_storage_gb" => 0 } }
      ])

      expect(rows_of(service.estimate(plan: plan), "storage")).to be_empty
    end
  end

  # ---- (c) egress: the larger phantom ---------------------------------------

  describe "egress lines" do
    it "emits NO egress line when the step declares no egress allowance" do
      plan = build_plan(steps: [
        { "skill" => "provision_full_stack", "inputs" => { "count" => 3 } }
      ])

      expect(rows_of(service.estimate(plan: plan), "network")).to be_empty
    end

    it "prices a declared egress allowance" do
      plan = build_plan(steps: [
        { "skill" => "provision_full_stack", "inputs" => { "count" => 2, "egress_gb" => 200 } }
      ])

      egress = rows_of(service.estimate(plan: plan), "network")
      expect(egress.size).to eq(1)
      # 200GB × 2 × $0.09/GB
      expect(egress.first[:monthly_usd]).to eq(36.0)
    end
  end

  # ---- confidence knock-on (deliberate, kept) --------------------------------

  describe "confidence" do
    it "reports low confidence for an unpinned step instead of high on phantom lines" do
      plan = build_plan(steps: [
        { "skill" => "provision_full_stack", "inputs" => { "count" => 3 } }
      ])

      result = service.estimate(plan: plan)
      expect(result[:monthly_usd]).to eq(0.0)
      # Nothing here could be priced — say so, rather than reporting "high"
      # confidence in a fabricated $42/mo.
      expect(result[:confidence]).to eq("low")
    end

    it "still counts a genuinely declared volume as something it priced" do
      plan = build_plan(steps: [
        { "skill" => "provision_full_stack", "inputs" => { "count" => 2, "with_storage_gb" => 100 } }
      ])

      result = service.estimate(plan: plan)
      expect(result[:monthly_usd]).to eq(20.0)
      expect(result[:confidence]).not_to eq("low")
    end
  end

  # ---- (d) docker legs must not each bill a whole fleet ----------------------

  describe "docker_provision legs" do
    it "contributes no compute line at all — it configures instances it did not create" do
      # PlanComposerService#synthesize_docker_legs! creates ONE docker_provision
      # step PER INSTANCE, each carrying only { "brief" => brief }, and
      # DockerProvisionExecutor#perform takes a node_instance_id and FAILS when
      # that instance does not exist. The leg provisions nothing, so its whole
      # cost is already carried by the provision step that made the instance.
      # Inheriting brief.scale.initial made every leg re-bill the entire fleet.
      plan = build_plan(steps: [
        { "skill" => "docker_provision", "inputs" => { "brief" => default_brief } }
      ])

      result = service.estimate(plan: plan)
      expect(rows_of(result, "compute")).to be_empty
      expect(rows_of(result, "storage")).to be_empty
      expect(rows_of(result, "network")).to be_empty
      expect(result[:monthly_usd]).to eq(0.0)
    end

    it "does not bill a docker leg even when one carries an explicit count" do
      plan = build_plan(steps: [
        { "skill" => "docker_provision", "inputs" => { "count" => 2, "brief" => default_brief } }
      ])

      expect(rows_of(service.estimate(plan: plan), "compute")).to be_empty
    end

    it "POSITIVE CONTROL: provision_full_stack still inherits the brief's fleet size" do
      plan = build_plan(steps: [
        { "skill" => "provision_full_stack", "inputs" => { "brief" => default_brief } }
      ])

      expect(rows_of(service.estimate(plan: plan), "compute").first[:count]).to eq(3)
    end
  end

  # ---- (e) scale_project reaches the priced path -----------------------------

  describe "scale_project" do
    it "is priced rather than reported unpriceable" do
      # AdaptationProposerService stamps `target_count` as a DELTA (the number
      # of NEW instances) alongside scaling_strategy. It is the only skill that
      # service threads with_storage_gb onto, and it priced to nothing.
      step = double("Step", execution_config: {
        "skill" => "scale_project",
        "inputs" => { "target_count" => 2, "scaling_strategy" => "add_replicas" }
      })

      result = service.estimate_step(step: step, brief: default_brief)
      expect(result[:unpriceable]).to be false
      compute = result[:by_resource].select { |r| r[:resource_type] == "compute" }
      expect(compute.size).to eq(1)
      expect(compute.first[:count]).to eq(2)
    end

    it "prices the volume a scale-out carries on with_storage_gb" do
      plan = build_plan(steps: [
        { "skill" => "scale_project",
          "inputs" => { "target_count" => 2, "scaling_strategy" => "add_replicas",
                        "with_storage_gb" => 50 } }
      ])

      storage = rows_of(service.estimate(plan: plan), "storage")
      expect(storage.size).to eq(1)
      expect(storage.first[:monthly_usd]).to eq(10.0) # 50GB × 2 × $0.10
    end

    it "does not inherit the brief's fleet size when the delta is absent" do
      plan = build_plan(steps: [
        { "skill" => "scale_project", "inputs" => { "brief" => default_brief } }
      ])

      expect(rows_of(service.estimate(plan: plan), "compute")).to be_empty
    end

    # The skill offers four arms and ALL of them carry a target_count. Only the
    # additive ones create instances; pricing a scale-IN or an in-place resize
    # as new compute would be a fabricated line of exactly the kind this task
    # removes — and worse than the old behaviour, which priced scale_project at
    # nothing at all.
    %w[remove_replicas vertical_resize].each do |strategy|
      it "quotes no new compute for the non-additive #{strategy} arm" do
        plan = build_plan(steps: [
          { "skill" => "scale_project",
            "inputs" => { "target_count" => 5, "scaling_strategy" => strategy } }
        ])

        result = service.estimate(plan: plan)
        expect(rows_of(result, "compute")).to be_empty
        expect(result[:monthly_usd]).to eq(0.0)
      end
    end

    it "does not quote a delta when the strategy is unstated" do
      # scaling_strategy is a REQUIRED executor input, so a step without one
      # fails at execution and provisions nothing.
      plan = build_plan(steps: [
        { "skill" => "scale_project", "inputs" => { "target_count" => 5 } }
      ])

      expect(rows_of(service.estimate(plan: plan), "compute")).to be_empty
    end

    it "POSITIVE CONTROL: prices the additive add_region arm" do
      plan = build_plan(steps: [
        { "skill" => "scale_project",
          "inputs" => { "target_count" => 3, "scaling_strategy" => "add_region" } }
      ])

      expect(rows_of(service.estimate(plan: plan), "compute").first[:count]).to eq(3)
    end
  end
end
