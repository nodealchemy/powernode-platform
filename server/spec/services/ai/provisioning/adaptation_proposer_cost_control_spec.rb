# frozen_string_literal: true

require "rails_helper"

# IMP-e68a93c47106 — INC-4 landed half against the producer/consumer law.
#
# `ScaleProjectExecutor::STRATEGIES` gained `remove_replicas` (the ACTUATOR),
# but this composer's `cost_control` arm still returned `[]` and
# UNSUPPORTED_CHANGE_TYPES still advertised "no scale-in strategy available".
# A verb with no lane in front of it — the mirror image of INC-1's actuator
# with no opener.
#
# This spec pins the wired lane AND the rail that must survive it:
#
#   COMPOSES — a cost breach emits a `scale_project` step carrying the
#              executor's three required kwargs and the REMOVAL strategy.
#   NEVER AUTO-APPLIES — the destructive step is ineligible for unattended
#              application, proven at the PREDICATE (#auto_apply?) and again at
#              the ACTUATION boundary (AdaptationDispatchService), including
#              against a gate that grants auto-apply on POLICY authority. The
#              one thing that DOES release it — a person who approved the
#              request — is pinned too, so the difference between the two is
#              explicit rather than assumed.
#   MIXED PLANS — one additive step beside one destructive step is still
#              ineligible, because the bounds check is an ALLOWLIST evaluated
#              over EVERY step, not the first one.
RSpec.describe Ai::Provisioning::AdaptationProposerService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  let(:default_brief) do
    {
      "intent" => "Spin up a 3-region web stack",
      "scale" => { "initial" => 3, "target" => 5 },
      "regions" => %w[us-east-1 us-west-2 eu-west-1],
      "budget_cap_usd_monthly" => 200.0
    }
  end

  let(:watch_policies) { { "auto_scale_max_replicas" => 5 } }

  let(:provisioning_footprint) do
    {
      "template_id" => "tmpl-fixture",
      "provider_region_id" => "region-fixture",
      "provider_instance_type_id" => "itype-fixture"
    }
  end

  def stamp_provisioning_plan!(target)
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Provision",
      description: "initial provisioning", goal_type: "improvement",
      status: "pending", priority: 3, progress: 0.0,
      success_criteria: {}, metadata: {}
    )
    plan = Ai::GoalPlan.create!(
      account: account, goal: goal, agent: agent, status: "draft",
      version: 1, plan_data: { "kind" => "provisioning" }
    )
    plan.steps.create!(
      step_number: 1, step_type: "provisioning_skill", status: "pending",
      description: "Provision full stack",
      execution_config: { "skill" => "provision_full_stack",
                          "inputs" => provisioning_footprint,
                          "on_failure" => "rollback" },
      dependencies: []
    )
    target.update!(configuration: target.configuration.merge("plan" => { "plan_id" => plan.id }))
    target
  end

  let!(:mission) do
    m = create(
      :ai_mission,
      account: account,
      created_by: user,
      mission_type: "infrastructure",
      custom_phases: [ { "key" => "adapting", "label" => "Adapting", "order" => 0 } ],
      configuration: {
        "brief" => default_brief,
        "slo_targets" => { "cost_ceiling_usd" => 200.0 },
        "watch_policies" => watch_policies
      }
    )
    m.update_columns(status: "active")
    stamp_provisioning_plan!(m.reload)
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  def cost_signal(breach_pct: 40.0, observed_usd: 280.0)
    double(
      "Signal",
      kind: "system.project_cost_breach",
      severity: :medium,
      payload: {
        "mission_id" => mission.id,
        "observed_usd" => observed_usd,
        "target_usd" => 200.0,
        "breach_pct" => breach_pct,
        "correlation_id" => "project_slo:#{mission.id}:cost"
      },
      fingerprint: "project_cost_breach:#{mission.id}"
    )
  end

  def step_inputs(plan, index = 0)
    plan.steps.in_order.to_a[index].execution_config["inputs"]
  end

  before do
    # Heuristic path only — the LLM seam never composes for a deterministic
    # change type, and stubbing it keeps that independent of provider fixtures.
    allow_any_instance_of(described_class).to receive(:diff_from_llm).and_return(nil)
  end

  # -------------------------------------------------------------------------
  # The lane: cost_control now COMPOSES.
  # -------------------------------------------------------------------------
  describe "the cost_control arm" do
    it "composes a scale_project step naming the removal strategy" do
      plan = service.propose_from_signals(signals: [ cost_signal ])

      expect(plan).to be_a(Ai::GoalPlan)
      step = plan.steps.in_order.first
      expect(step.execution_config["skill"]).to eq("scale_project")
      expect(step.execution_config["composed_by"]).to eq("deterministic")
      expect(step_inputs(plan)["scaling_strategy"]).to eq(described_class::REMOVAL_STRATEGY)
      expect(step_inputs(plan)["change_type"]).to eq("cost_control")
    end

    it "carries the executor's three required kwargs, so the step can bind" do
      plan = service.propose_from_signals(signals: [ cost_signal ])
      inputs = step_inputs(plan)

      described_class::SCALE_PROJECT_REQUIRED_INPUTS.each do |key|
        expect(inputs[key]).to be_present, "expected composed step to carry #{key}"
      end
      expect(inputs["project_id"]).to eq(mission.id)
    end

    it "sizes the removal off the breach ladder rather than a fixed constant" do
      modest = service.propose_from_signals(signals: [ cost_signal(breach_pct: 40.0) ])
      severe = described_class.new(account: account, mission: mission.reload)
        .propose_from_signals(signals: [ cost_signal(breach_pct: 60.0) ])

      expect(step_inputs(modest)["target_count"]).to eq(1)
      expect(step_inputs(severe)["target_count"]).to eq(2)
    end

    it "composes WITHOUT a compute footprint — a removal creates nothing" do
      # The scale-OUT arm declines when template/region/instance-type are
      # unresolved because new replicas cannot be provisioned without them.
      # A removal names no template at all, so the same absence must not
      # silence it.
      mission.update!(configuration: mission.configuration.except("plan"))

      plan = described_class.new(account: account, mission: mission.reload)
        .propose_from_signals(signals: [ cost_signal ])

      expect(plan).not_to be_nil
      expect(step_inputs(plan)["scaling_strategy"]).to eq(described_class::REMOVAL_STRATEGY)
      expect(step_inputs(plan)).not_to have_key("template_id")
    end

    it "does not stamp desired_replica_count — a removal has no absolute target" do
      # `desired_replica_count` is the policy-facing ABSOLUTE the scale-out
      # arm reports. A removal's target_count is a DELTA the executor resolves
      # against the live fleet; inventing an absolute here would hand
      # #auto_apply? a number to measure.
      plan = service.propose_from_signals(signals: [ cost_signal ])
      expect(step_inputs(plan)).not_to have_key("desired_replica_count")
    end

    it "describes the step as a removal rather than as a replica target" do
      plan = service.propose_from_signals(signals: [ cost_signal ])
      expect(plan.steps.in_order.first.description).to match(/remove/i)
    end

    it "lets an operator request a cost_control adaptation instead of raising" do
      result = service.propose_change(change_type: "cost_control",
                                      details: { "target_usd" => 200.0, "breach_pct" => 40.0 })

      expect(result[:plan]).to be_a(Ai::GoalPlan)
      expect(result[:change_type]).to eq("cost_control")
      expect(step_inputs(result[:plan])["scaling_strategy"])
        .to eq(described_class::REMOVAL_STRATEGY)
    end
  end

  # -------------------------------------------------------------------------
  # The rail: REMOVALS NEVER AUTO-APPLY (ratified readiness map §7).
  # -------------------------------------------------------------------------
  describe "a plan containing a remove_replicas step" do
    it "is not eligible for unattended application" do
      plan = service.propose_from_signals(signals: [ cost_signal ])

      expect(plan.steps.count).to be >= 1
      expect(service.auto_apply?(plan: plan)).to be false
    end

    it "stays ineligible even with a replica ceiling that would clear a scale-out" do
      # The ceiling is what the scale-OUT arm is measured against. A removal
      # must be ineligible BY CONSTRUCTION, not because it happened to land
      # outside somebody's bound.
      mission.update!(configuration: mission.configuration.merge(
        "watch_policies" => { "auto_scale_max_replicas" => 500 }
      ))
      svc = described_class.new(account: account, mission: mission.reload)
      plan = svc.propose_from_signals(signals: [ cost_signal ])

      # Guard against passing vacuously on a nil plan — `auto_apply?(nil)` is
      # false for a reason that has nothing to do with removals.
      expect(plan).not_to be_nil
      expect(svc.auto_apply?(plan: plan)).to be false
    end

    it "is ineligible when it rides ALONGSIDE an in-bounds additive step" do
      # A per-step check that only inspected the FIRST step would pass here.
      # The additive step is first and is in bounds on its own.
      allow_any_instance_of(described_class).to receive(:diff_from_llm).and_return([
        { "skill" => "scale_project", "on_failure" => "rollback",
          "inputs" => { "project_id" => mission.id, "target_count" => 1,
                        "scaling_strategy" => "add_replicas",
                        "change_type" => "scale_horizontal",
                        "desired_replica_count" => 4 } },
        { "skill" => "scale_project", "on_failure" => "rollback",
          "inputs" => { "project_id" => mission.id, "target_count" => 2,
                        "scaling_strategy" => described_class::REMOVAL_STRATEGY } }
      ])

      # schema_change is the operator-only lane the LLM still composes, so a
      # mixed plan is reachable there.
      result = service.propose_change(change_type: "schema_change")
      plan = result[:plan]

      strategies = plan.steps.in_order.map { |s| s.execution_config.dig("inputs", "scaling_strategy") }
      expect(strategies).to include("add_replicas", described_class::REMOVAL_STRATEGY)
      expect(service.auto_apply?(plan: plan)).to be false
    end
  end

  # -------------------------------------------------------------------------
  # The TERMINAL oracle — the predicate is core's input to the gate, but what
  # matters is that nothing is destroyed unattended at the actuation boundary.
  # -------------------------------------------------------------------------
  describe "dispatching a cost_control plan" do
    let(:dispatcher) { Ai::Provisioning::AdaptationDispatchService.new(account: account, mission: mission) }

    before { allow(::Powernode::ExtensionRegistry).to receive(:provider).and_call_original }

    def stub_gate(gate)
      allow(::Powernode::ExtensionRegistry).to receive(:provider)
        .with(:adaptation_gate).and_return(gate)
    end

    it "hands the gate auto_apply_eligible: false and parks for a decision" do
      captured = nil
      gate = double("adaptation_gate")
      allow(gate).to receive(:adaptation_disposition) do |**kwargs|
        captured = kwargs
        { disposition: "routed", approval_request_id: "req-1" }
      end
      stub_gate(gate)

      plan = service.propose_from_signals(signals: [ cost_signal ])
      result = dispatcher.dispatch!(plan: plan)

      expect(captured[:auto_apply_eligible]).to be false
      expect(result[:gate]).to eq("routed")
      expect(result[:dispatched]).to be false
    end

    it "REFUSES a gate that tries to auto-apply the removal on policy authority" do
      gate = double("adaptation_gate")
      allow(gate).to receive(:adaptation_disposition)
        .and_return({ disposition: "auto_apply_within_bounds" })
      stub_gate(gate)

      plan = service.propose_from_signals(signals: [ cost_signal ])
      result = dispatcher.dispatch!(plan: plan)

      expect(result[:gate]).to eq("parked_gate_unavailable")
      expect(result[:dispatched]).to be false
      expect(plan.reload.status).to eq("draft")
    end

    it "DOES release the removal once a person has approved it" do
      # The counterpart to the refusal above, pinned so the two are told apart
      # by the DECLARED authority rather than by luck. Core's bounds check
      # exists to stop the MACHINE destroying replicas unattended — not to veto
      # an operator who looked at the plan and said yes. If this example ever
      # goes red because approval stopped working, the `routed` lane has become
      # a dead end for exactly the plans that most need a person.
      gate = double("adaptation_gate")
      allow(gate).to receive(:adaptation_disposition).and_return(
        { disposition: "auto_apply_within_bounds", authority: "approval" }
      )
      allow(gate).to receive(:record_adaptation_outcome!).and_return(nil)
      stub_gate(gate)
      allow(WorkerJobService).to receive(:enqueue_job).and_return(true)

      plan = service.propose_from_signals(signals: [ cost_signal ])
      result = dispatcher.dispatch!(plan: plan)

      expect(result[:gate]).to eq("auto_apply_within_bounds")
    end
  end

  # -------------------------------------------------------------------------
  # The retained refusal seam must stay load-bearing, not become a monument.
  # -------------------------------------------------------------------------
  describe "UNSUPPORTED_CHANGE_TYPES" do
    it "still refuses an operator request for any change type listed in it" do
      # The entry that used to prove this guard worked was cost_control's, and
      # deleting it left the mechanism with no behavioural oracle at all. This
      # exercises the guard itself, so the next requestable-but-unactuatable
      # change type inherits a mechanism that is known to fire.
      stub_const("#{described_class}::UNSUPPORTED_CHANGE_TYPES",
                 { "relocate" => "relocate has no composer yet" })

      expect { service.propose_change(change_type: "relocate") }
        .to raise_error(described_class::UnsupportedChangeTypeError,
                        /relocate has no composer yet/)
    end
  end
end
