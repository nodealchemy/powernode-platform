# frozen_string_literal: true

require "rails_helper"

# Golden Eclipse M0 — ProvisioningTool MCP surface.
# Mirrors the system_fleet_tool_spec.rb shape: invoke .execute(params:) directly,
# assert success_result/error_result content. Service layer (IntentCaptureService,
# PlanComposerService, SkillCompositionRunner) is stubbed so the tool's
# routing + persistence logic is the unit under test. Compose routes through
# Ai::Missions::ComposerRouter — a provisioning-shaped brief selects
# PlanComposerService; a novel intent selects MissionComposer.
RSpec.describe Ai::Tools::ProvisioningTool do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:agent)   { create(:ai_agent, account: account) }
  let(:tool)    { described_class.new(account: account, agent: agent, user: user) }

  # Minimal system_provisioning template — the seed creates a 7-phase template
  # but the tool only needs capture_intent, compose_plan, review_plan, execute
  # to validate the phase transitions exercised in this spec.
  let!(:provisioning_template) do
    ::Ai::MissionTemplate.find_or_create_by!(
      name: described_class::MISSION_TEMPLATE_NAME, template_type: "system"
    ) do |t|
      t.account = nil
      t.description = "test fixture"
      t.mission_type = "infrastructure"
      t.status = "active"
      t.is_default = true
      t.version = 1
      t.phases = [
        { "order" => 0, "key" => "capture_intent",  "label" => "Capture",  "requires_approval" => false },
        { "order" => 1, "key" => "compose_plan",    "label" => "Compose",  "requires_approval" => false },
        { "order" => 2, "key" => "review_plan",     "label" => "Review",   "requires_approval" => true },
        { "order" => 3, "key" => "execute",         "label" => "Execute",  "requires_approval" => false }
      ]
      t.approval_gates = %w[review_plan]
      t.rejection_mappings = { "review_plan" => "compose_plan" }
      t.skill_compositions = {}
      t.default_configuration = {}
    end
  end

  # M1 Self-Serve Hardening — when the business extension is loaded the
  # provisioning_tool consults Billing::ProvisioningQuotaGuard before
  # dispatching the SkillCompositionRunner. The pre-existing tool tests
  # don't model a subscription, so allow the guard for these specs.
  before do
    if defined?(::Billing::ProvisioningQuotaGuard)
      allow(::Billing::ProvisioningQuotaGuard).to receive(:allow?).and_return([true, nil])
    end
  end

  def call(action, **rest)
    tool.execute(params: { action: action }.merge(rest))
  end

  # --------------------------------------------------------------------------
  # Static surface
  # --------------------------------------------------------------------------

  describe ".action_definitions" do
    # platform_provisioning_execute was removed — approve_plan is the
    # canonical execute trigger via the orchestrator. A separate execute
    # action raced with that path and double-provisioned (early-M1 bug).
    it "registers all 5 platform_provisioning_* actions" do
      keys = described_class.action_definitions.keys
      expect(keys).to contain_exactly(
        "platform_provisioning_capture_brief",
        "platform_provisioning_compose_plan",
        "platform_provisioning_approve_plan",
        "platform_provisioning_status",
        "platform_provisioning_adapt"
      )
    end

    it "every action has a description and parameters Hash" do
      described_class.action_definitions.each do |action_name, defn|
        expect(defn[:description]).to be_present, "missing description for #{action_name}"
        expect(defn[:parameters]).to be_a(Hash),    "missing parameters Hash for #{action_name}"
      end
    end
  end

  describe "Registry wiring" do
    it "is registered in PlatformApiToolRegistry::TOOLS for all 5 actions" do
      %w[
        platform_provisioning_capture_brief
        platform_provisioning_compose_plan
        platform_provisioning_approve_plan
        platform_provisioning_status
        platform_provisioning_adapt
      ].each do |action|
        expect(Ai::Tools::PlatformApiToolRegistry::TOOLS[action]).to eq("Ai::Tools::ProvisioningTool")
      end
    end
  end

  # --------------------------------------------------------------------------
  # platform_provisioning_capture_brief
  # --------------------------------------------------------------------------

  describe "platform_provisioning_capture_brief" do
    let(:fake_brief) do
      {
        "intent" => "Provision a 3-node Postgres cluster",
        "use_case" => nil,
        "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
        "regions" => ["us-east-1"],
        "compliance" => [],
        "budget_cap_usd_monthly" => 500.0,
        "latency_targets_ms" => { "p99" => 100 },
        "data_residency" => [],
        "preferred_provider" => nil
      }
    end

    before do
      allow_any_instance_of(::Ai::Provisioning::IntentCaptureService)
        .to receive(:capture).and_return(brief: fake_brief, missing_fields: [:use_case])
      allow_any_instance_of(::Ai::Provisioning::IntentCaptureService)
        .to receive(:refine).and_return(brief: fake_brief.merge("use_case" => "OLTP"), missing_fields: [])
    end

    it "creates a new infrastructure mission and persists the brief when no mission_id" do
      r = call(
        "platform_provisioning_capture_brief",
        natural_language: "provision 3 postgres nodes us-east-1"
      )
      expect(r[:success]).to be true

      mission = ::Ai::Mission.find(r[:data][:mission_id])
      expect(mission.mission_type).to eq("infrastructure")
      expect(mission.mission_template).to eq(provisioning_template)
      expect(mission.current_phase).to eq("capture_intent")
      expect(mission.created_by).to eq(user)
      expect(mission.configuration["brief"]).to eq(fake_brief)
      expect(r[:data][:brief]).to eq(fake_brief)
      expect(r[:data][:missing_fields]).to include(:use_case)
    end

    it "refines an existing mission's brief when mission_id is provided" do
      mission = create_mission!(brief: fake_brief)

      r = call(
        "platform_provisioning_capture_brief",
        mission_id: mission.id,
        natural_language: "OLTP workload"
      )
      expect(r[:success]).to be true
      expect(r[:data][:mission_id]).to eq(mission.id)
      expect(r[:data][:brief]["use_case"]).to eq("OLTP")
      expect(r[:data][:missing_fields]).to be_empty
    end

    it "returns an error when natural_language is blank" do
      r = call("platform_provisioning_capture_brief", natural_language: "")
      expect(r[:success]).to be false
      expect(r[:error]).to include("natural_language")
    end

    it "rejects mission_id from another account" do
      other_account = create(:account)
      other_user = create(:user, account: other_account)
      other_mission = create_mission!(account: other_account, user: other_user)

      r = call(
        "platform_provisioning_capture_brief",
        mission_id: other_mission.id,
        natural_language: "x"
      )
      expect(r[:success]).to be false
      expect(r[:error]).to include("not found")
    end

    it "rejects mission_id pointing at a non-infrastructure mission" do
      dev_mission = account.ai_missions.create!(
        name: "Dev mission", mission_type: "research",
        repository: nil, created_by: user,
        configuration: {}
      )
      r = call(
        "platform_provisioning_capture_brief",
        mission_id: dev_mission.id,
        natural_language: "x"
      )
      expect(r[:success]).to be false
      expect(r[:error]).to include("not an infrastructure mission")
    end
  end

  # --------------------------------------------------------------------------
  # platform_provisioning_compose_plan
  # --------------------------------------------------------------------------

  describe "platform_provisioning_compose_plan" do
    it "delegates to PlanComposerService and returns the DAG plus M1 enrichments" do
      mission = create_mission!(brief: { "intent" => "x", "preferred_provider" => "aws" })
      goal = create_goal_for(mission)
      plan = create_plan_with_step!(goal, skill: "provision_full_stack")

      expect_any_instance_of(::Ai::Provisioning::PlanComposerService)
        .to receive(:compose!).and_return(plan)

      r = call("platform_provisioning_compose_plan", mission_id: mission.id)
      expect(r[:success]).to be true
      expect(r[:data][:plan_id]).to eq(plan.id)
      expect(r[:data][:dag][:nodes].first[:skill]).to eq("provision_full_stack")

      cost = r[:data][:cost_estimate]
      expect(cost).to be_a(Hash)
      expect(cost.keys).to include(:monthly_usd, :one_time_usd, :by_resource, :confidence)
      expect(cost[:by_resource]).to be_an(Array)
      expect(cost[:confidence]).to be_in(%w[high med low])

      topo = r[:data][:topology_preview]
      expect(topo).to be_a(Hash)
      expect(topo.keys).to include(:nodes, :edges, :regions, :estimated_resources)
      expect(topo[:nodes]).to be_an(Array)

      risk = r[:data][:risk]
      expect(risk).to be_a(Hash)
      expect(risk.keys).to include(:score, :severity, :factors)
      expect(risk[:severity]).to be_in(%w[low med high])
      expect(risk[:score]).to be_between(0, 100)
    end

    it "routes a novel/general intent to MissionComposer (not PlanComposerService)" do
      mission = create_mission!(brief: { "intent" => "orchestrate a federated multi-cluster mesh" })
      goal = create_goal_for(mission)
      plan = create_plan_with_step!(goal, skill: "provision_full_stack")

      expect_any_instance_of(::Ai::Missions::MissionComposer)
        .to receive(:compose!).and_return(plan)
      expect(::Ai::Provisioning::PlanComposerService).not_to receive(:new)

      r = call("platform_provisioning_compose_plan", mission_id: mission.id)
      expect(r[:success]).to be true
      expect(r[:data][:plan_id]).to eq(plan.id)
    end

    it "surfaces BriefMissingError as an error_result" do
      mission = create_mission!(brief: { "intent" => "x", "preferred_provider" => "aws" })
      expect_any_instance_of(::Ai::Provisioning::PlanComposerService)
        .to receive(:compose!)
        .and_raise(::Ai::Provisioning::PlanComposerService::BriefMissingError.new("no brief"))

      r = call("platform_provisioning_compose_plan", mission_id: mission.id)
      expect(r[:success]).to be false
      expect(r[:error]).to include("no brief")
    end

    it "errors when mission_id is missing" do
      r = call("platform_provisioning_compose_plan")
      expect(r[:success]).to be false
    end

    context "M2 BYOC routing — multi-provider clarification" do
      it "forwards the PlanComposer clarification payload as a success_result" do
        mission = create_mission!(brief: { "intent" => "x", "regions" => ["us-east-1"] })

        clarification = {
          clarification_needed: true,
          message: "I see you have multiple cloud providers configured (AWS, Hetzner). Which would you like to use?",
          available_providers: [
            { id: "00000000-0000-0000-0000-000000000001", name: "AWS-prod", type: "aws" },
            { id: "00000000-0000-0000-0000-000000000002", name: "Hetzner-prod", type: "hetzner" }
          ]
        }

        expect_any_instance_of(::Ai::Provisioning::PlanComposerService)
          .to receive(:compose!).and_return(clarification)

        r = call("platform_provisioning_compose_plan", mission_id: mission.id)
        expect(r[:success]).to be true
        expect(r[:data][:clarification_needed]).to be true
        expect(r[:data][:message]).to include("multiple cloud providers")
        expect(r[:data][:available_providers].map { |p| p[:type] })
          .to match_array(%w[aws hetzner])
        expect(r[:data][:mission_id]).to eq(mission.id)
        # The plan keys should NOT be present on a clarification result
        expect(r[:data][:plan_id]).to be_nil
        expect(r[:data][:dag]).to be_nil
      end

      it "does not advance the mission past compose_plan when clarification is returned" do
        mission = create_mission!(brief: { "intent" => "x", "regions" => ["us-east-1"] }, phase: "compose_plan")

        expect_any_instance_of(::Ai::Provisioning::PlanComposerService)
          .to receive(:compose!).and_return(
            clarification_needed: true,
            message: "Which provider?",
            available_providers: []
          )

        call("platform_provisioning_compose_plan", mission_id: mission.id)
        expect(mission.reload.current_phase).to eq("compose_plan")
      end
    end
  end

  # --------------------------------------------------------------------------
  # platform_provisioning_approve_plan
  # --------------------------------------------------------------------------

  describe "platform_provisioning_approve_plan" do
    it "advances the mission past review_plan when decision='approved'" do
      mission = create_mission!(phase: "review_plan")
      goal = create_goal_for(mission)
      plan = create_plan_with_step!(goal)

      r = call("platform_provisioning_approve_plan", plan_id: plan.id, decision: "approved")
      expect(r[:success]).to be true
      expect(mission.reload.current_phase).to eq("execute")
      expect(r[:data][:approval_request_id]).to be_nil
      expect(r[:data][:mission_status]).to eq(mission.status)
    end

    it "sends the mission back to compose_plan when decision='rejected'" do
      mission = create_mission!(phase: "review_plan")
      goal = create_goal_for(mission)
      plan = create_plan_with_step!(goal)

      r = call("platform_provisioning_approve_plan", plan_id: plan.id, decision: "rejected")
      expect(r[:success]).to be true
      expect(mission.reload.current_phase).to eq("compose_plan")
    end

    it "applies inline modifications when decision='modified'" do
      mission = create_mission!(phase: "review_plan")
      goal = create_goal_for(mission)
      plan = create_plan_with_step!(goal, skill: "provision_full_stack")

      r = call(
        "platform_provisioning_approve_plan",
        plan_id: plan.id,
        decision: "modified",
        modifications: { "steps" => [{ "step_number" => 1, "skill" => "provision_cluster" }] }
      )
      expect(r[:success]).to be true
      expect(mission.reload.current_phase).to eq("execute")
      expect(plan.steps.find_by(step_number: 1).execution_config["skill"]).to eq("provision_cluster")
    end

    it "ignores modifications referencing skills outside the allowlist" do
      mission = create_mission!(phase: "review_plan")
      goal = create_goal_for(mission)
      plan = create_plan_with_step!(goal, skill: "provision_full_stack")

      call(
        "platform_provisioning_approve_plan",
        plan_id: plan.id,
        decision: "modified",
        modifications: { "steps" => [{ "step_number" => 1, "skill" => "rm_rf_slash" }] }
      )
      expect(plan.steps.find_by(step_number: 1).execution_config["skill"]).to eq("provision_full_stack")
    end

    it "rejects an unknown decision value" do
      mission = create_mission!(phase: "review_plan")
      goal = create_goal_for(mission)
      plan = create_plan_with_step!(goal)

      r = call("platform_provisioning_approve_plan", plan_id: plan.id, decision: "yolo")
      expect(r[:success]).to be false
      expect(r[:error]).to include("decision must be")
    end

    it "rejects plan_id from another account" do
      other_account = create(:account)
      other_user = create(:user, account: other_account)
      other_mission = create_mission!(account: other_account, user: other_user, phase: "review_plan")
      other_goal = create_goal_for(other_mission, account: other_account, user: other_user)
      other_plan = create_plan_with_step!(other_goal, account: other_account, user: other_user)

      r = call("platform_provisioning_approve_plan", plan_id: other_plan.id, decision: "approved")
      expect(r[:success]).to be false
    end
  end

  # --------------------------------------------------------------------------
  # platform_provisioning_status
  # --------------------------------------------------------------------------

  describe "platform_provisioning_status" do
    it "returns mission phase + step lists for a plan with mixed statuses" do
      mission = create_mission!(phase: "execute")
      goal = create_goal_for(mission)
      plan = ::Ai::GoalPlan.create!(
        account: account, goal: goal, agent: agent,
        status: "executing", version: 1
      )
      step_attrs = { plan: plan, step_type: "provisioning_skill", step_number: 1 }
      ::Ai::GoalPlanStep.create!(step_attrs.merge(status: "completed",
                                                  execution_config: { "skill" => "provision_full_stack" }))
      ::Ai::GoalPlanStep.create!(step_attrs.merge(status: "executing", step_number: 2,
                                                  execution_config: { "skill" => "drift_remediate" }))
      ::Ai::GoalPlanStep.create!(step_attrs.merge(status: "pending", step_number: 3,
                                                  execution_config: { "skill" => "capacity_recommend" }))
      ::Ai::GoalPlanStep.create!(step_attrs.merge(status: "failed", step_number: 4,
                                                  execution_config: { "skill" => "docker_provision" }))

      r = call("platform_provisioning_status", mission_id: mission.id)
      expect(r[:success]).to be true
      expect(r[:data][:phase]).to eq("execute")
      expect(r[:data][:current_step]).to eq(2)
      expect(r[:data][:completed]).to eq([1])
      expect(r[:data][:pending]).to eq([3])
      expect(r[:data][:failed]).to eq([4])
    end

    it "returns empty lists when no plan exists yet" do
      mission = create_mission!(phase: "capture_intent")
      r = call("platform_provisioning_status", mission_id: mission.id)
      expect(r[:success]).to be true
      expect(r[:data][:completed]).to be_empty
      expect(r[:data][:pending]).to be_empty
      expect(r[:data][:failed]).to be_empty
      expect(r[:data][:current_step]).to be_nil
    end
  end

  # --------------------------------------------------------------------------
  # platform_provisioning_adapt — wired to AdaptationProposerService
  #
  # The M0 stub ({ todo: "M2", adaptation_plan: nil }) is gone: the action now
  # funnels an explicit operator change request through the SAME internal path
  # the sensor-driven proposer uses, so the diff plan is persisted and routed
  # through Ai::Autonomy::ApprovalWorkflowService as
  # `project.adapt_<change_type>`. Approval routing is never bypassed.
  # --------------------------------------------------------------------------

  describe "platform_provisioning_adapt" do
    # Keep the proposer hermetic — nil from the LLM seam makes it use the
    # deterministic heuristic step builder (same convention as
    # spec/services/ai/provisioning/adaptation_proposer_service_spec.rb).
    before do
      allow_any_instance_of(::Ai::Provisioning::AdaptationProposerService)
        .to receive(:diff_from_llm).and_return(nil)
    end

    # `let!` so the fixture plan exists BEFORE any example body runs —
    # otherwise plan-count assertions would capture this fixture's plan.
    let!(:adapt_mission) do
      m = create_mission!(brief: {
        "intent" => "3-node web stack",
        "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
        "regions" => %w[us-east-1 us-west-2]
      })
      # Production shape: the mission carries the provisioning plan whose
      # provision step names the footprint (template / region / instance
      # type) a scale-out must replicate. Without it the adaptation composer
      # declines rather than emitting a step the scaling skill would reject.
      goal = create_goal_for(m)
      plan = ::Ai::GoalPlan.create!(
        account: account, goal: goal, agent: agent, status: "draft",
        version: 1, plan_data: { "kind" => "provisioning" }
      )
      plan.steps.create!(
        step_number: 1, step_type: "provisioning_skill", status: "pending",
        description: "Provision full stack",
        execution_config: {
          "skill" => "provision_full_stack",
          "inputs" => { "template_id" => "tmpl-fixture",
                        "provider_region_id" => "region-fixture",
                        "provider_instance_type_id" => "itype-fixture" },
          "on_failure" => "rollback"
        },
        dependencies: []
      )
      m.update!(configuration: m.configuration.merge("plan" => { "plan_id" => plan.id }))
      m
    end

    # IMP-8c37b9e5ccd5 (INC-2): the operator MCP path joins the SAME queue —
    # `adapt` now hands its composed plan to
    # Ai::Provisioning::AdaptationDispatchService, which resolves the
    # `adaptation_gate` seam. With no gate registered the plan parks; a stubbed
    # gate is how an example asks for a specific disposition.
    def stub_gate(disposition, approval_request_id: nil)
      gate = double("adaptation_gate")
      allow(gate).to receive(:adaptation_disposition)
        .and_return({ disposition: disposition, approval_request_id: approval_request_id })
      allow(gate).to receive(:record_adaptation_outcome!).and_return(nil)
      allow(::Powernode::ExtensionRegistry).to receive(:provider).and_call_original
      allow(::Powernode::ExtensionRegistry).to receive(:provider)
        .with(:adaptation_gate).and_return(gate)
      gate
    end

    it "no longer advertises the M0 stub in its action definition" do
      defn = described_class.action_definitions["platform_provisioning_adapt"]
      expect(defn[:description]).not_to match(/todo/i)
      expect(defn[:description]).not_to match(/M0 stub/i)
      expect(defn[:description]).to match(/approval|gate/i)
      expect(defn[:parameters]).to have_key(:change_type)
    end

    # The defect this replaces: `approval: { requested: approval.present? }`
    # collapsed "no approval was needed" and "the approval system is not there
    # at all" into one `false`, inside a success payload that implies the change
    # is on its way. An operator reading it could not tell an applied change
    # from a parked one. The envelope now names the disposition.
    it "reports parked_gate_unavailable when no adaptation gate is registered" do
      allow(::Powernode::ExtensionRegistry).to receive(:provider).and_call_original
      allow(::Powernode::ExtensionRegistry).to receive(:provider)
        .with(:adaptation_gate).and_return(nil)

      r = call("platform_provisioning_adapt",
               mission_id: adapt_mission.id,
               change_type: "scale_horizontal",
               details: { "breach_pct" => 100.0, "replica_count" => 3 })

      expect(r[:success]).to be true
      expect(r[:data][:gate][:disposition]).to eq("parked_gate_unavailable")
      expect(r[:data][:gate][:dispatched]).to be false
      expect(r[:data][:gate][:detail]).to be_present
      # Ground truth: parked means parked.
      expect(::Ai::GoalPlan.find(r[:data][:plan_id]).status).to eq("draft")
    end

    it "reports routed with the approval request id when the gate holds the plan" do
      request_id = SecureRandom.uuid
      stub_gate("routed", approval_request_id: request_id)

      r = call("platform_provisioning_adapt",
               mission_id: adapt_mission.id,
               change_type: "scale_horizontal",
               details: { "breach_pct" => 100.0, "replica_count" => 3 })

      expect(r[:data][:gate][:disposition]).to eq("routed")
      expect(r[:data][:gate][:approval_request_id]).to eq(request_id)
      expect(r[:data][:gate][:dispatched]).to be false
      expect(r[:data][:gate][:action_type]).to eq("project.adapt_scale_horizontal")
      expect(::Ai::GoalPlan.find(r[:data][:plan_id]).status).to eq("draft")
    end

    it "dispatches onto the live plan when the gate grants auto-apply within bounds" do
      allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
      stub_gate("auto_apply_within_bounds")
      # An unattended auto-apply requires the mission to declare a ceiling for
      # core's bounds check; without one core parks the plan no matter what the
      # gate answers (asserted in the relocate example below).
      adapt_mission.update!(configuration: adapt_mission.configuration.merge(
        "watch_policies" => { "auto_scale_max_replicas" => 8 }
      ))
      live_plan_id = adapt_mission.configuration.dig("plan", "plan_id")
      before_steps = ::Ai::GoalPlan.find(live_plan_id).steps.count

      r = call("platform_provisioning_adapt",
               mission_id: adapt_mission.id,
               change_type: "scale_horizontal",
               details: { "breach_pct" => 100.0, "replica_count" => 3 })

      expect(r[:data][:gate][:disposition]).to eq("auto_apply_within_bounds")
      expect(r[:data][:gate][:dispatched]).to be true
      # Ground truth: the live plan actually grew, and a step job went out.
      expect(::Ai::GoalPlan.find(live_plan_id).steps.count).to eq(before_steps + 1)
      expect(WorkerJobService).to have_received(:enqueue_job).with("AiProvisioningStepJob", anything)
    end

    it "composes a real diff plan and reports the gate outcome" do
      stub_gate("routed", approval_request_id: SecureRandom.uuid)

      r = call("platform_provisioning_adapt",
               mission_id: adapt_mission.id,
               change_type: "scale_horizontal",
               metric: "p99_latency_ms",
               # replica_count: the operator path has no sensor to observe the
               # fleet, so the caller supplies it. Without it the proposer
               # declines rather than guessing from the brief.
               details: { "breach_pct" => 100.0, "observed" => 500.0, "target" => 250.0,
                          "replica_count" => 3 })

      expect(r[:success]).to be true
      expect(r[:data]).not_to have_key(:todo)
      expect(r[:data][:mission_id]).to eq(adapt_mission.id)
      expect(r[:data][:change_type]).to eq("scale_horizontal")

      plan = ::Ai::GoalPlan.find(r[:data][:plan_id])
      expect(plan.account_id).to eq(account.id)
      expect(plan.plan_data["kind"]).to eq("adaptation_diff")
      expect(plan.plan_data["change_type"]).to eq("scale_horizontal")
      expect(plan.steps.pluck(:step_type)).to all(eq("provisioning_skill"))

      adaptation_plan = r[:data][:adaptation_plan]
      expect(adaptation_plan[:id]).to eq(plan.id)
      expect(adaptation_plan[:step_count]).to eq(plan.steps.count)
      first_step = adaptation_plan[:steps].first
      expect(first_step[:skill]).to eq("scale_project")
      expect(first_step[:inputs]["change_type"]).to eq("scale_horizontal")
      expect(first_step[:inputs]["desired_replica_count"]).to eq(5) # initial 3 + breach 100% → +2
      # The explicit request is funnelled through the same signal-shaped
      # envelope the sensor path uses, so the operator's metric/details land
      # under signal_payload for the downstream skill executor.
      expect(first_step[:inputs]["signal_payload"]["metric"]).to eq("p99_latency_ms")
      expect(first_step[:inputs]["signal_payload"]["observed"]).to eq(500.0)
      expect(first_step[:inputs]["correlation_id"]).to be_present

      expect(r[:data][:gate][:disposition]).to eq("routed")
      expect(r[:data][:gate][:action_type]).to eq("project.adapt_scale_horizontal")
      expect(r[:data][:gate][:approval_request_id]).to be_present
      # The indistinguishable boolean is gone for good.
      expect(r[:data]).not_to have_key(:approval)
      expect(r[:data][:summary]).to be_present
    end

    it "fails an operator cost_control request with a clear reason rather than an unbindable plan" do
      # Was: asserted a composed cost_control plan whose first step named
      # `scale_project`. That step carried none of the skill's required
      # kwargs, so approving it produced "missing required input:
      # project_id" at execution. A cost breach implies scaling IN and no
      # scale-in strategy exists yet, so the proposer declines and the
      # operator gets an immediate, explicit failure instead.
      # INC-4 (IMP-216a6dbc7e32) adds `remove_replicas`; restore then.
      gate = stub_gate("auto_apply_within_bounds")

      r = call("platform_provisioning_adapt",
               mission_id: adapt_mission.id,
               change_type: "cost_control",
               details: { "target_usd" => 200.0 })

      expect(r[:success]).to be false
      expect(r[:error]).to include("cost_control")
      expect(gate).not_to have_received(:adaptation_disposition)
    end

    it "parks a relocate behind the gate rather than applying it" do
      # A relocate is never eligible for auto-apply: the bounds check is an
      # allowlist of the one additive scale-out strategy, so core hands the
      # gate auto_apply_eligible: false and the plan waits.
      captured = nil
      gate = double("adaptation_gate")
      allow(gate).to receive(:adaptation_disposition) do |**kw|
        captured = kw
        { disposition: "routed", approval_request_id: SecureRandom.uuid }
      end
      allow(::Powernode::ExtensionRegistry).to receive(:provider).and_call_original
      allow(::Powernode::ExtensionRegistry).to receive(:provider)
        .with(:adaptation_gate).and_return(gate)

      # relocate_workload declares 8 required inputs. The heuristic composer
      # supplies none of them and does NOT thread `details` into step inputs,
      # so a complete proposal has to arrive through the composition seam or
      # the step is dropped as unbindable — leaving no plan for this
      # example's actual subject (approval routing) to examine.
      allow_any_instance_of(::Ai::Provisioning::AdaptationProposerService)
        .to receive(:diff_from_llm).and_return([
          { "skill" => "relocate_workload",
            "inputs" => { "project_id" => adapt_mission.id, "from_region_id" => "r1",
                          "to_region_id" => "r2", "cutover_strategy" => "blue_green",
                          "template_id" => "tmpl-fixture",
                          "provider_instance_type_id" => "itype-fixture",
                          "count" => 2, "source_instance_ids" => %w[i-1] },
            "on_failure" => "rollback" }
        ])

      r = call("platform_provisioning_adapt",
               mission_id: adapt_mission.id,
               change_type: "relocate")

      expect(r[:success]).to be true
      expect(r[:data][:plan_id]).to be_present
      expect(r[:data][:gate][:disposition]).to eq("routed")
      expect(r[:data][:gate][:dispatched]).to be false
      expect(captured[:auto_apply_eligible]).to be false
      expect(r[:data][:adaptation_plan][:steps].first[:skill]).to eq("relocate_workload")
      expect(::Ai::GoalPlan.find(r[:data][:plan_id]).status).to eq("draft")
    end

    it "accepts the legacy proposed_change envelope" do
      stub_gate("routed")

      r = call("platform_provisioning_adapt",
               mission_id: adapt_mission.id,
               proposed_change: { "kind" => "scale_horizontal", "breach_pct" => 100.0,
                                  "replica_count" => 3 })

      expect(r[:success]).to be true
      expect(r[:data][:change_type]).to eq("scale_horizontal")
      expect(r[:data][:adaptation_plan][:steps].first[:inputs]["desired_replica_count"]).to eq(5)
    end

    it "returns a clean error envelope for an unknown mission_id" do
      expect {
        r = call("platform_provisioning_adapt",
                 mission_id: SecureRandom.uuid,
                 change_type: "scale_horizontal")
        expect(r[:success]).to be false
        expect(r[:error]).to include("not found")
        expect(r[:data]).to be_nil
      }.not_to change(::Ai::GoalPlan, :count)
    end

    it "rejects a mission_id belonging to another account" do
      other_account = create(:account)
      other_user = create(:user, account: other_account)
      other_mission = create_mission!(account: other_account, user: other_user)

      expect {
        r = call("platform_provisioning_adapt",
                 mission_id: other_mission.id,
                 change_type: "scale_horizontal")
        expect(r[:success]).to be false
        expect(r[:error]).to include("not found")
      }.not_to change(::Ai::GoalPlan, :count)
    end

    it "rejects an unknown change_type without composing a plan" do
      expect {
        r = call("platform_provisioning_adapt",
                 mission_id: adapt_mission.id,
                 change_type: "delete_everything")
        expect(r[:success]).to be false
        expect(r[:error]).to include("change_type")
        expect(r[:error]).to include("scale_horizontal")
      }.not_to change(::Ai::GoalPlan, :count)
    end

    it "requires a change_type" do
      r = call("platform_provisioning_adapt", mission_id: adapt_mission.id)
      expect(r[:success]).to be false
      expect(r[:error]).to include("change_type")
    end
  end

  # --------------------------------------------------------------------------
  # Unknown action
  # --------------------------------------------------------------------------

  describe "Unknown action" do
    it "returns an error_result" do
      r = call("definitely_not_real")
      expect(r[:success]).to be false
      expect(r[:error]).to include("Unknown action")
    end
  end

  # ==========================================================================
  # Helpers
  # ==========================================================================

  def create_mission!(account: nil, user: nil, brief: nil, phase: "capture_intent")
    acct = account || self.account
    usr  = user || (acct == self.account ? self.user : create(:user, account: acct))
    cfg  = brief ? { "brief" => brief } : {}
    acct.ai_missions.create!(
      name: "Test mission #{SecureRandom.hex(2)}",
      mission_type: "infrastructure",
      status: "draft",
      mission_template: provisioning_template,
      current_phase: phase,
      objective: "test",
      created_by: usr,
      configuration: cfg
    )
  end

  def create_goal_for(mission, account: nil, user: nil)
    acct = account || self.account
    ag   = acct == self.account ? agent : create(:ai_agent, account: acct)
    ::Ai::AgentGoal.create!(
      account: acct,
      agent: ag,
      title: "Provisioning goal",
      description: "test",
      goal_type: "creation",
      status: "pending",
      priority: 3,
      progress: 0.0,
      success_criteria: { "mission_id" => mission.id },
      metadata: { "provisioning_mission_id" => mission.id }
    )
  end

  def create_plan_with_step!(goal, skill: "provision_full_stack", account: nil, user: nil)
    acct = account || goal.account
    ag   = acct == self.account ? agent : create(:ai_agent, account: acct)
    plan = ::Ai::GoalPlan.create!(
      account: acct, goal: goal, agent: ag,
      status: "draft", version: 1
    )
    ::Ai::GoalPlanStep.create!(
      plan: plan, step_number: 1,
      step_type: "provisioning_skill", status: "pending",
      execution_config: { "skill" => skill, "inputs" => {}, "on_failure" => "rollback" },
      dependencies: []
    )
    plan
  end
end
