# frozen_string_literal: true

require "rails_helper"

# Golden Eclipse M0 — ProvisioningTool MCP surface.
# Mirrors the system_fleet_tool_spec.rb shape: invoke .execute(params:) directly,
# assert success_result/error_result content. Service layer (IntentCaptureService,
# PlanComposerService, SkillCompositionRunner) is stubbed so the tool's
# routing + persistence logic is the unit under test.
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
    it "registers all 6 platform_provisioning_* actions" do
      keys = described_class.action_definitions.keys
      expect(keys).to contain_exactly(
        "platform_provisioning_capture_brief",
        "platform_provisioning_compose_plan",
        "platform_provisioning_approve_plan",
        "platform_provisioning_execute",
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
    it "is registered in PlatformApiToolRegistry::TOOLS for all 6 actions" do
      %w[
        platform_provisioning_capture_brief
        platform_provisioning_compose_plan
        platform_provisioning_approve_plan
        platform_provisioning_execute
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
      mission = create_mission!(brief: { "intent" => "x" })
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

    it "surfaces BriefMissingError as an error_result" do
      mission = create_mission!
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
        mission = create_mission!(brief: { "intent" => "x" })

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
        mission = create_mission!(brief: { "intent" => "x" }, phase: "compose_plan")

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
  # platform_provisioning_execute
  # --------------------------------------------------------------------------

  describe "platform_provisioning_execute" do
    it "delegates to SkillCompositionRunner.execute! and returns runner metadata" do
      mission = create_mission!
      goal = create_goal_for(mission)
      _plan = create_plan_with_step!(goal)

      time = Time.utc(2026, 5, 6, 12, 0, 0)
      expect_any_instance_of(::Ai::Provisioning::SkillCompositionRunner)
        .to receive(:execute!)
        .and_return(runner_id: "run-1", started_at: time, step_count: 3)

      r = call("platform_provisioning_execute", mission_id: mission.id)
      expect(r[:success]).to be true
      expect(r[:data][:runner_id]).to eq("run-1")
      expect(r[:data][:started_at]).to eq(time.iso8601)
      expect(r[:data][:step_count]).to eq(3)
    end

    it "errors when no plan exists for the mission" do
      mission = create_mission!
      r = call("platform_provisioning_execute", mission_id: mission.id)
      expect(r[:success]).to be false
      expect(r[:error]).to include("compose_plan first")
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
  # platform_provisioning_adapt — M0 stub
  # --------------------------------------------------------------------------

  describe "platform_provisioning_adapt" do
    it "returns the M0 stub regardless of inputs" do
      mission = create_mission!
      r = call("platform_provisioning_adapt",
               mission_id: mission.id,
               proposed_change: { "kind" => "scale_horizontal" })
      expect(r[:success]).to be true
      expect(r[:data][:todo]).to eq("M2")
      expect(r[:data][:adaptation_plan]).to be_nil
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
