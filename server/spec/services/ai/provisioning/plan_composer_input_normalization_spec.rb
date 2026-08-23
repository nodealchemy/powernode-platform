# frozen_string_literal: true

require "rails_helper"

# IMP-1fc00ac8547a — #merge_resolved_inputs! normalizes inputs for an
# ALLOWLIST of skill names, and returns on its first line for everything else.
# The allowlist is a NAME LIST, so a skill added to the composer's reachable
# set (ALLOWED_EXECUTORS + STATIC_ACTION_MAP) and not also added to
# TEMPLATE_RESOLVING_SKILLS composes with NONE of the inputs its executor
# DECLARES required — silently, with no operator- or spec-visible signal.
#
# Silence is the defect. These examples pin three things:
#
#   1. The two already-normalized skills are BYTE-IDENTICAL — the regression
#      bar for any change to the dispatch. Pinned as whole-hash equality, not
#      key presence, so a mutation of the dispatch cannot pass through.
#   2. `provision_cluster` — composer-reachable TODAY, declaring the SAME four
#      required inputs as `provision_full_stack` — is normalized.
#   3. An omission that remains (a reachable skill declaring an input the
#      composer knows how to resolve, neither stamped nor wired from an
#      upstream step) is RECORDED: an operator sees it in the log and a spec
#      sees it on the persisted step.
RSpec.describe Ai::Provisioning::PlanComposerService, "input normalization coverage", type: :service do
  before { skip "system extension not loaded" unless defined?(::System::Ai::Skills::ProvisionClusterExecutor) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:ai_provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: ai_provider, creator: user, status: "active")
  end

  # `initial` is deliberately NOT 1: with 1, a mutation replacing the brief
  # read with the literal default would produce the same answer and pass.
  # The brief NAMES its region and template so both resolve deterministically
  # rather than landing on whatever the account bootstrap happened to seed.
  let(:brief) do
    { "scale" => { "initial" => 3 }, "regions" => [ "spec-region" ],
      "preferred_template" => "spec-template" }
  end
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        configuration: { "brief" => brief })
  end

  # Records the resolvers must actually land on, so the expectations below are
  # pinned to IDENTITIES this example owns rather than to whatever the service
  # happens to return. Computing the expected ids by calling the service's own
  # resolvers would be circular: a mutation inside a resolver would move both
  # sides of the comparison together and pass.
  #
  # One dedicated provider, so the instance-type lookup (scoped by the
  # region's provider_id) can only find this one.
  let!(:provider) { create(:system_provider, account: account) }
  let!(:region) do
    create(:system_provider_region, account: account, provider: provider,
                                    region_code: "spec-region", name: "spec-region")
  end
  let!(:instance_type) do
    create(:system_provider_instance_type, account: account, provider: provider, hourly_price: 0.01)
  end
  let!(:template) { create(:system_node_template, account: account, name: "spec-template") }

  subject(:service) { described_class.new(account: account, mission: mission) }

  def normalized_for(skill)
    inputs = {}
    service.send(:merge_resolved_inputs!, inputs, brief, skill)
    inputs
  end

  describe "the byte-identical regression bar" do
    # Whole-hash equality against independently-created records: an added,
    # dropped, renamed or re-pointed key all go red.
    let(:fully_normalized) do
      {
        "count" => 3,
        "dry_run" => false,
        "provider_region_id" => region.id,
        "provider_instance_type_id" => instance_type.id,
        "template_id" => template.id,
        "mission_id" => mission.id
      }
    end

    it "stamps provision_full_stack with exactly the normalized key set and values" do
      expect(normalized_for("provision_full_stack")).to eq(fully_normalized)
    end

    it "stamps scale_project with exactly the normalized key set and values" do
      expect(normalized_for("scale_project")).to eq(fully_normalized)
    end

    it "produces byte-identical output for the two already-normalized skills" do
      expect(normalized_for("provision_full_stack")).to eq(normalized_for("scale_project"))
    end

    # `||=` precedence is load-bearing three separate times in
    # #merge_resolved_inputs! (a step's own template_id must outrank the
    # brief's, an operator-supplied value must always win) and is untestable
    # from an empty inputs hash — every `||=` behaves like `=` there. Pin it.
    it "never overwrites inputs the step already carries" do
      preset = { "template_id" => "step-owned", "count" => 99, "dry_run" => true,
                 "provider_region_id" => "step-region" }
      service.send(:merge_resolved_inputs!, preset, brief, "provision_full_stack")

      expect(preset["template_id"]).to eq("step-owned")
      expect(preset["count"]).to eq(99)
      expect(preset["dry_run"]).to be(true)
      expect(preset["provider_region_id"]).to eq("step-region")
    end
  end

  # The standing example of the gap. provision_cluster is on the composer's
  # action map and declares the SAME four inputs provision_full_stack does,
  # yet gets none of them. It is deliberately NOT added to the allowlist —
  # doing so without the fan-out and collapse passes would trade a loud
  # dispatch failure for silent over-provisioning — so what this task
  # guarantees is that the gap is REPORTED, not that it is closed.
  describe "provision_cluster (declares the same four inputs, still unnormalized)" do
    it "is on the composer's own action map" do
      expect(described_class::ALLOWED_EXECUTORS).to include("provision_cluster")
      expect(service.send(:map_action_to_skill, "stand up a cluster")).to eq("provision_cluster")
    end

    it "declares the four inputs the normalization resolves" do
      required = Ai::Provisioning::SkillCompositionRunner.required_inputs_for("provision_cluster")
      expect(required).to include("template_id", "count", "provider_region_id", "provider_instance_type_id")
    end

    it "still receives no normalization" do
      expect(normalized_for("provision_cluster")).to eq({})
    end
  end

  # The guard that makes the NEXT omission loud rather than latent. Driven by
  # the executor's DECLARED required inputs (through the same slug->executor
  # seam dispatch uses), never by a name list — so a skill added to the
  # composer cannot skip normalization without something saying so.
  describe "#record_unnormalized_inputs!" do
    def plan_with_step(skill, inputs: {}, depends_on_outputs: nil)
      goal = Ai::AgentGoal.create!(
        account: account, agent: agent, title: "Provisioning goal", description: "test",
        goal_type: "creation", status: "pending", priority: 3, progress: 0.0,
        success_criteria: { "mission_id" => mission.id },
        metadata: { "provisioning_mission_id" => mission.id }
      )
      plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                                  status: "draft", version: 1)
      cfg = { "skill" => skill, "inputs" => inputs }
      cfg["depends_on_outputs"] = depends_on_outputs if depends_on_outputs
      Ai::GoalPlanStep.create!(
        plan: plan, step_number: 1, step_type: "provisioning_skill",
        status: "pending", dependencies: [], execution_config: cfg
      )
      plan
    end

    it "records every omitted key on an unnormalized provision_cluster step" do
      plan = plan_with_step("provision_cluster")

      expect(Rails.logger).to receive(:error).with(/provision_cluster.*not in TEMPLATE_RESOLVING_SKILLS/m)
      service.send(:record_unnormalized_inputs!, plan)

      expect(plan.steps.reload.first.execution_config["unnormalized_inputs"])
        .to match_array(%w[template_id count provider_region_id provider_instance_type_id])
    end

    it "records the omitted key on an advisory skill that declares one" do
      # capacity_recommend is in ALLOWED_EXECUTORS, is matched by
      # STATIC_ACTION_MAP (/recommend/), and DECLARES template_id required —
      # an input #merge_resolved_inputs! knows how to resolve but never
      # stamps for this skill.
      plan = plan_with_step("capacity_recommend")

      expect(Rails.logger).to receive(:error).with(/capacity_recommend.*template_id/m)
      service.send(:record_unnormalized_inputs!, plan)

      expect(plan.steps.reload.first.execution_config["unnormalized_inputs"]).to eq([ "template_id" ])
    end

    # Presence follows DISPATCH's oracle (BaseSkillExecutor rejects only nil),
    # so a legitimately blank or zero value is supplied, not omitted.
    it "does not report a key whose value is blank or zero" do
      plan = plan_with_step("capacity_recommend", inputs: { "template_id" => "" })
      allow(Rails.logger).to receive(:error)
      service.send(:record_unnormalized_inputs!, plan)

      expect(plan.steps.reload.first.execution_config).not_to have_key("unnormalized_inputs")
    end

    it "stays silent for a normalized skill" do
      plan = plan_with_step("provision_full_stack", inputs: { "template_id" => "t", "count" => 1,
                                                              "provider_region_id" => "r",
                                                              "provider_instance_type_id" => "i" })
      expect(Rails.logger).not_to receive(:error)
      service.send(:record_unnormalized_inputs!, plan)

      expect(plan.steps.reload.first.execution_config).not_to have_key("unnormalized_inputs")
    end

    # docker_provision / deploy_app_code take node_instance_id from an
    # UPSTREAM step's outputs, which cannot exist at compose time. A wired key
    # is supplied, not omitted, and must not be reported.
    it "stays silent for a key wired from an upstream step's outputs" do
      plan = plan_with_step(
        "docker_provision",
        depends_on_outputs: { "node_instance_id" => { "from_step" => 1, "path" => "outputs.node_instance_ids" } }
      )
      expect(Rails.logger).not_to receive(:error)
      service.send(:record_unnormalized_inputs!, plan)

      expect(plan.steps.reload.first.execution_config).not_to have_key("unnormalized_inputs")
    end

    # Only keys the composer could actually have resolved. node_instance_id is
    # not one of them, so an unwired docker_provision step is a wiring defect
    # for #wire_docker_provision_steps! to report, not a normalization omission.
    it "reports only keys the normalization knows how to resolve" do
      plan = plan_with_step("docker_provision")
      allow(Rails.logger).to receive(:error)
      service.send(:record_unnormalized_inputs!, plan)

      expect(plan.steps.reload.first.execution_config).not_to have_key("unnormalized_inputs")
    end

    # Core mode: no executors are loaded, so requirements are UNRESOLVABLE.
    # "I cannot tell what this needs" must not be reported as an omission —
    # and must stay distinguishable from "this needs nothing" ([]), which the
    # seam pays to keep separate.
    it "stays silent when the skill's requirements cannot be resolved" do
      plan = plan_with_step("provision_cluster")
      allow(Ai::Provisioning::SkillCompositionRunner).to receive(:required_inputs_for).and_return(nil)

      expect(Rails.logger).not_to receive(:error)
      service.send(:record_unnormalized_inputs!, plan)

      expect(plan.steps.reload.first.execution_config).not_to have_key("unnormalized_inputs")
    end

    it "stays silent when the skill declares no required inputs" do
      plan = plan_with_step("provision_cluster")
      allow(Ai::Provisioning::SkillCompositionRunner).to receive(:required_inputs_for).and_return([])

      expect(Rails.logger).not_to receive(:error)
      service.send(:record_unnormalized_inputs!, plan)

      expect(plan.steps.reload.first.execution_config).not_to have_key("unnormalized_inputs")
    end

    # The audit must reach plans composed BEFORE it existed. #compact_existing_plan!
    # is the operator-facing read path — every deep-link view of a cached plan.
    it "runs on the cached-plan read path, not only at compose time" do
      plan = plan_with_step("provision_cluster")
      allow(Rails.logger).to receive(:error)

      service.compact_existing_plan!(plan)

      expect(plan.steps.reload.first.execution_config["unnormalized_inputs"])
        .to include("template_id")
    end

    # The durable half of "loud" is only loud if something serves it.
    it "is served on the plan DAG the operator's plan-review surface reads" do
      plan = plan_with_step("provision_cluster")
      allow(Rails.logger).to receive(:error)
      service.send(:record_unnormalized_inputs!, plan)

      snapshot = Ai::Provisioning::PlanSnapshotService.new(account: account)
      node = snapshot.send(:build_dag, plan.reload)[:nodes].first

      expect(node[:unnormalized_inputs]).to include("template_id")
    end

    it "adds no DAG field for a healthy step" do
      plan = plan_with_step("provision_full_stack", inputs: { "template_id" => "t", "count" => 1,
                                                              "provider_region_id" => "r",
                                                              "provider_instance_type_id" => "i" })
      service.send(:record_unnormalized_inputs!, plan)

      snapshot = Ai::Provisioning::PlanSnapshotService.new(account: account)
      node = snapshot.send(:build_dag, plan.reload)[:nodes].first

      expect(node).not_to have_key(:unnormalized_inputs)
    end
  end
end
