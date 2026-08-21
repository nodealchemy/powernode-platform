# frozen_string_literal: true

require "rails_helper"

# IMP-02b4bc9f8bd8 (INC-3) — the heuristic composer's scale_horizontal output
# was never integrated against the actuator it names (`scale_project`).
#
# Three facets, one root:
#
#   F1 — CONVERGENCE. #recommended_replica_count read only `breach_pct` and
#        composed from `brief.scale.initial`, ignoring the drift payload's
#        `observed`/`target` entirely. Sensor-emitted replica_count drift
#        carries no breach_pct, so the step was always +1 — and since
#        ProjectSloSensor derives `expected_replica_count` FROM
#        `brief.scale.initial`, the proposal was always exactly one ABOVE
#        the target no matter what was observed. It never converged, and it
#        re-fired every tick (a ratchet once a reconciler is wired).
#
#   F2 — EXECUTOR CONTRACT. The composed step carried an absolute
#        `desired_replica_count` and none of the kwargs the executor
#        actually requires (`project_id`, `target_count`, `scaling_strategy`,
#        plus template/region/instance-type). `target_count` is a DELTA
#        ("number of new instances"), not an absolute count.
#
#   F3 — NETWORK + STORAGE. The scale path supplied neither `network_id` nor
#        `with_storage_gb`, so a dispatched scale-out was compute-only — no
#        SDWAN peer, no volume — even though the underlying provisioning
#        primitive threads both and reports peer/volume ids in its outputs.
#        Note this is specifically about the `scale_project` path: SDWAN does
#        exist in this service, but only as a SEPARATE step type
#        (`configure_sdwan_for_project`) bound to change class
#        `security_change`, which no scale or drift signal ever selects.
RSpec.describe Ai::Provisioning::AdaptationProposerService, "convergence + executor contract" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  # brief.scale.initial is what ProjectSloSensor uses as expected_replica_count,
  # so target == 2 in every drift payload below is the realistic pairing.
  let(:brief) do
    {
      "intent" => "small web stack",
      "scale" => { "initial" => 2, "target" => 4, "growth_profile" => "linear" },
      "regions" => %w[us-east-1],
      "budget_cap_usd_monthly" => 200.0
    }
  end

  let(:watch_policies) { { "auto_scale_max_replicas" => 8 } }

  # The mission's ORIGINAL provisioning plan. Its provision step is the
  # authoritative record of the footprint the mission already runs — the
  # template, region and instance type to replicate when scaling out, and
  # (F3) the SDWAN network and per-instance volume size.
  let(:original_footprint) do
    {
      "template_id" => "tmpl-aaa",
      "provider_region_id" => "region-bbb",
      "provider_instance_type_id" => "itype-ccc",
      "network_id" => "net-ddd",
      "with_storage_gb" => 50
    }
  end

  def build_original_plan!(inputs:)
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent,
      title: "Provision", description: "initial provisioning",
      goal_type: "improvement", status: "pending", priority: 3, progress: 0.0,
      success_criteria: {}, metadata: {}
    )
    plan = Ai::GoalPlan.create!(
      account: account, goal: goal, agent: agent,
      status: "draft", version: 1, plan_data: { "kind" => "provisioning" }
    )
    plan.steps.create!(
      step_number: 1, step_type: "provisioning_skill", status: "pending",
      description: "Provision full stack",
      execution_config: { "skill" => "provision_full_stack", "inputs" => inputs,
                          "on_failure" => "rollback" },
      dependencies: []
    )
    plan
  end

  def build_mission!(with_plan: true, footprint: original_footprint,
                     observations: nil, policies: watch_policies)
    configuration = {
      "brief" => brief,
      "slo_targets" => { "availability_pct" => 99.5, "p99_latency_ms" => 250,
                         "cost_ceiling_usd" => 200.0 },
      "watch_policies" => policies
    }
    configuration["latest_observations"] = observations if observations
    mission = create(
      :ai_mission,
      account: account, created_by: user, mission_type: "infrastructure",
      custom_phases: [ { "key" => "adapting", "label" => "Adapting", "order" => 0 } ],
      configuration: configuration
    )
    mission.update_columns(status: "active")

    if with_plan
      plan = build_original_plan!(inputs: footprint)
      mission.update!(configuration: mission.configuration.merge(
        "plan" => { "plan_id" => plan.id }
      ))
    end
    mission.reload
  end

  # Sensor-shaped replica_count drift. Note there is deliberately NO
  # breach_pct key — ProjectSloSensor#drift_signal does not emit one, which
  # is exactly what made the old `payload["breach_pct"].to_f` read 0.0.
  def drift_signal(observed:, target:, mission:)
    double(
      "Signal",
      kind: "system.project_drift",
      severity: :medium,
      payload: {
        "mission_id" => mission.id,
        "drift_type" => "replica_count",
        "observed" => observed,
        "target" => target,
        "correlation_id" => "project_slo:#{mission.id}:conv"
      },
      fingerprint: "project_drift:#{mission.id}:replica_count"
    )
  end

  # `replica_count` is what ProjectSloSensor now stamps onto every SLO
  # violation: `observed` here is the breached METRIC (latency), so the fleet
  # size has to ride alongside it. `nil` means the sensor could not see the
  # fleet, which is NOT the same as "the fleet is at its declared size".
  def slo_signal(mission:, breach_pct: 100.0, replica_count: 2)
    double(
      "Signal",
      kind: "system.project_slo_violation",
      severity: :high,
      payload: {
        "mission_id" => mission.id,
        "metric" => "p99_latency_ms",
        "observed" => 500.0,
        "target" => 250.0,
        "breach_pct" => breach_pct,
        "replica_count" => replica_count,
        "correlation_id" => "project_slo:#{mission.id}:slo"
      },
      fingerprint: "project_slo_violation:#{mission.id}:p99_latency_ms"
    )
  end

  def step_inputs(plan)
    plan.steps.in_order.first.execution_config.deep_stringify_keys["inputs"]
  end

  before do
    # Heuristic path only — this task is about the heuristic composer.
    allow_any_instance_of(described_class).to receive(:diff_from_llm).and_return(nil)
  end

  # ---------------------------------------------------------------------
  # F1 — converge to target, don't step
  # ---------------------------------------------------------------------
  describe "F1: drift composes toward the target from the OBSERVED count" do
    it "scales UP to exactly the target when under-provisioned" do
      mission = build_mission!
      service = described_class.new(account: account, mission: mission)

      plan = service.propose_from_signals(
        signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
      )

      expect(plan).to be_a(Ai::GoalPlan)
      inputs = step_inputs(plan)
      # Ground truth: the composed absolute count IS the target (2), not
      # brief.scale.initial + 1 (which was 3 — an overshoot that re-fires).
      expect(inputs["desired_replica_count"]).to eq(2)
      # And the executor-facing DELTA closes exactly the observed gap.
      expect(inputs["target_count"]).to eq(1)
    end

    it "proposes NOTHING on a second pass over the converged state" do
      mission = build_mission!
      service = described_class.new(account: account, mission: mission)

      # First pass: observed 1, target 2 → a converging plan.
      first = service.propose_from_signals(
        signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
      )
      expect(first).to be_a(Ai::GoalPlan)

      # Second pass over the state the first pass converges to (observed
      # now equals target). This is the assertion that actually proves
      # convergence rather than mere direction: a converged system must
      # produce no plan at all.
      second = described_class.new(account: account, mission: mission.reload)
        .propose_from_signals(
          signals: [ drift_signal(observed: 2, target: 2, mission: mission) ]
        )
      expect(second).to be_nil
      expect(Ai::GoalPlan.where(account_id: account.id).count).to eq(2) # original + first only
    end

    it "does NOT ratchet upward on over-count drift" do
      mission = build_mission!
      service = described_class.new(account: account, mission: mission)

      # observed 3 > target 2. The old code composed 4 — the WRONG direction,
      # growing a fleet that is already too large. The executor exposes no
      # shrink strategy, so the correct behaviour is to compose nothing
      # rather than to scale further out.
      plan = service.propose_from_signals(
        signals: [ drift_signal(observed: 3, target: 2, mission: mission) ]
      )

      expect(plan).to be_nil
    end

    it "PRESERVES the SLO-violation path's intentional +1/+2 stepping" do
      mission = build_mission!
      service = described_class.new(account: account, mission: mission)

      # initial=2, breach_pct=100 (≥50) → +2 → 4. Deliberate stepping, not
      # convergence — an SLO breach has no replica "target" to converge on.
      plan = service.propose_from_signals(signals: [ slo_signal(mission: mission) ])
      inputs = step_inputs(plan)
      expect(inputs["desired_replica_count"]).to eq(4)
      expect(inputs["target_count"]).to eq(2)

      # Sub-50% breach → +1 → 3.
      mission2 = build_mission!
      plan2 = described_class.new(account: account, mission: mission2)
        .propose_from_signals(signals: [ slo_signal(mission: mission2, breach_pct: 30.0) ])
      expect(step_inputs(plan2)["desired_replica_count"]).to eq(3)
      expect(step_inputs(plan2)["target_count"]).to eq(1)
    end
  end

  # ---------------------------------------------------------------------
  # F2 — shape the composition to the real executor contract
  # ---------------------------------------------------------------------
  describe "F2: emits the scale_project executor's actual kwargs" do
    it "emits project_id, a DELTA target_count, and an explicit scaling_strategy" do
      mission = build_mission!
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
        )

      inputs = step_inputs(plan)
      expect(inputs["project_id"]).to eq(mission.id)
      expect(inputs["scaling_strategy"]).to eq("add_replicas")
      # target_count is "number of NEW instances" — a delta, bounded ≥ 1.
      # Asserting it is the gap (1) and NOT the absolute count (2) is the
      # whole point: passing the absolute here would over-provision.
      expect(inputs["target_count"]).to eq(1)
      expect(inputs["target_count"]).not_to eq(inputs["desired_replica_count"])
    end

    it "resolves template, region and instance type from the mission's own plan" do
      mission = build_mission!
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
        )

      inputs = step_inputs(plan)
      expect(inputs["template_id"]).to eq("tmpl-aaa")
      expect(inputs["provider_region_id"]).to eq("region-bbb")
      expect(inputs["provider_instance_type_id"]).to eq("itype-ccc")
    end
  end

  # ---------------------------------------------------------------------
  # F3 — thread network and storage on the scale path
  # ---------------------------------------------------------------------
  describe "F3: threads network_id + with_storage_gb on the scale_project path" do
    it "carries the mission's SDWAN network and per-instance volume size" do
      mission = build_mission!
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
        )

      inputs = step_inputs(plan)
      # Without these the dispatched scale-out is compute-only: the
      # provisioning primitive only creates a peer when network_id is
      # present and only provisions a volume when with_storage_gb is.
      expect(inputs["network_id"]).to eq("net-ddd")
      expect(inputs["with_storage_gb"]).to eq(50)
    end

    # The ALIAS lane. `with_storage_gb` is the canonical spelling and the one
    # PlanComposerService stamps (IMP-cdc1d0703e5a), but a plan composed by
    # MissionComposer — or authored by hand — may declare the size under the
    # bare `storage_gb` spelling. Every OTHER core reader of a step's inputs
    # accepts it (PlanSnapshotService, CostEstimatorService#declared_gb), and
    # the actuating executors resolve it at run time (ScaleProjectExecutor via
    # ProvisionFullStackExecutor.resolve_storage_gb). This service was the one
    # reader that did not, so a storage-bearing mission written that way
    # composed a COMPUTE-ONLY scale-out — precisely the "replicas come up bare"
    # failure #existing_footprint says it exists to prevent.
    it "reads the tolerated storage_gb alias off the original step" do
      mission = build_mission!(
        footprint: original_footprint.except("with_storage_gb").merge("storage_gb" => 75)
      )
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
        )

      expect(step_inputs(plan)["with_storage_gb"]).to eq(75)
    end

    # Positive twin, and the precedence half: `resolve_storage_gb` is
    # canonical-first, so a step carrying BOTH spellings must keep the
    # canonical value rather than letting the alias overwrite it.
    it "keeps the canonical value when the original step carries both spellings" do
      mission = build_mission!(footprint: original_footprint.merge("storage_gb" => 999))
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
        )

      expect(step_inputs(plan)["with_storage_gb"]).to eq(50)
    end

    # What separates NORMALIZING the alias from merely tolerating it, and the
    # reason `storage_gb` is not simply appended to FOOTPRINT_KEYS: the
    # footprint is merged straight into the composed step's inputs, and
    # `with_storage_gb` is the only storage spelling `scale_project` DECLARES
    # (ScaleProjectExecutor's declared inputs). Emitting the alias would make
    # the composed step depend on the executor's run-time tolerance instead of
    # its declared schema.
    it "emits only the declared spelling, never the alias" do
      mission = build_mission!(
        footprint: original_footprint.except("with_storage_gb").merge("storage_gb" => 75)
      )
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
        )

      expect(step_inputs(plan)).not_to have_key("storage_gb")
    end

    it "omits network/storage keys rather than emitting nils when the mission has neither" do
      mission = build_mission!(footprint: original_footprint.except("network_id", "with_storage_gb"))
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
        )

      inputs = step_inputs(plan)
      expect(inputs).not_to have_key("network_id")
      expect(inputs).not_to have_key("with_storage_gb")
      # The compute-side contract still holds.
      expect(inputs["template_id"]).to eq("tmpl-aaa")
    end
  end

  # ---------------------------------------------------------------------
  # The SLO path must step off the LIVE fleet, not the brief — otherwise
  # the auto-apply ceiling never binds and the SLO path becomes the same
  # ratchet the drift path just stopped being.
  # ---------------------------------------------------------------------
  describe "SLO stepping is anchored to the live fleet" do
    it "steps up from the OBSERVED replica count, not brief.scale.initial" do
      # brief.scale.initial is 2, but the fleet is actually at 5.
      mission = build_mission!
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ slo_signal(mission: mission, replica_count: 5) ]
        )

      inputs = step_inputs(plan)
      # breach 100 → +2 off the LIVE 5 → 7. Anchored to the brief it would
      # be a constant 4 forever, no matter how large the fleet grew.
      expect(inputs["desired_replica_count"]).to eq(7)
      expect(inputs["target_count"]).to eq(2)
    end

    it "lets auto_scale_max_replicas actually bind as the fleet grows" do
      # Ceiling 8. A fleet already at 7 would step to 9 — over the cap.
      mission = build_mission!
      service = described_class.new(account: account, mission: mission)
      plan = service.propose_from_signals(
        signals: [ slo_signal(mission: mission, replica_count: 7) ]
      )

      expect(step_inputs(plan)["desired_replica_count"]).to eq(9)
      # The ratchet showed up as auto_apply staying true forever while the
      # fleet grew past the cap. It must go false here.
      expect(service.auto_apply?(plan: plan)).to be false
    end

    it "DECLINES when the fleet is unobservable rather than using the brief" do
      # No replica_count on the signal means the sensor could not see the
      # fleet. Substituting brief.scale.initial here would make the baseline
      # a constant, so every tick would propose the same "within cap" number
      # while the fleet grew — the ratchet this whole task removes.
      mission = build_mission!
      expect(
        described_class.new(account: account, mission: mission)
          .propose_from_signals(
            signals: [ slo_signal(mission: mission, replica_count: nil) ]
          )
      ).to be_nil
    end
  end

  # ---------------------------------------------------------------------
  # Bounding a single step (the actuating skill rejects an over-bound delta)
  # ---------------------------------------------------------------------
  describe "a single scale-out step is bounded" do
    it "clamps target_count and reports the count the step actually REACHES" do
      mission = build_mission!(
        policies: watch_policies.merge("max_scale_out_delta" => 3)
      )
      service = described_class.new(account: account, mission: mission)
      plan = service.propose_from_signals(
        signals: [ drift_signal(observed: 1, target: 20, mission: mission) ]
      )

      inputs = step_inputs(plan)
      # Gap is 19; the ceiling is 3. Clamped — successive passes close the
      # rest, rather than composing a step the executor rejects outright.
      expect(inputs["target_count"]).to eq(3)
      # 1 + 3, NOT the unreachable 20. auto_apply? measures this against the
      # ceiling, so reporting 20 would refuse auto-apply for a step well
      # inside policy and strand the multi-pass convergence.
      expect(inputs["desired_replica_count"]).to eq(4)
      expect(service.auto_apply?(plan: plan)).to be true
      expect(plan.steps.in_order.first.description).to include("4 replicas")
    end

    it "does not let config raise the bound above the core-side ceiling" do
      # A mission asking for 100 against an actuator that refuses anything
      # over its own ceiling would compose exactly the unbindable step the
      # clamp exists to prevent. Config may only LOWER the bound.
      mission = build_mission!(
        policies: watch_policies.merge("max_scale_out_delta" => 100)
      )
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ drift_signal(observed: 1, target: 500, mission: mission) ]
        )

      expect(step_inputs(plan)["target_count"])
        .to eq(described_class::DEFAULT_MAX_SCALE_OUT_DELTA)
    end
  end

  # ---------------------------------------------------------------------
  # Composition is DETERMINISTIC-FIRST. These examples deliberately let the
  # LLM seam return a well-formed proposal — the production default is an
  # active provider credential, and under the old LLM-first order that
  # proposal won and shipped without the executor's required kwargs.
  # ---------------------------------------------------------------------
  describe "deterministic-first composition" do
    let(:llm_scale_proposal) do
      [ { "skill" => "scale_project",
          "inputs" => { "desired_replica_count" => 99 },
          "on_failure" => "rollback" } ]
    end

    it "uses the deterministic composer for drift even when the LLM proposes" do
      mission = build_mission!
      allow_any_instance_of(described_class)
        .to receive(:diff_from_llm).and_return(llm_scale_proposal)

      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
        )

      inputs = step_inputs(plan)
      # The LLM's 99 is discarded; the converging composition wins and
      # carries the executor kwargs the LLM never supplies.
      expect(inputs["desired_replica_count"]).to eq(2)
      expect(inputs["target_count"]).to eq(1)
      expect(inputs["project_id"]).to eq(mission.id)
      expect(inputs["scaling_strategy"]).to eq("add_replicas")
      expect(plan.steps.in_order.first.execution_config["composed_by"]).to eq("deterministic")
    end

    it "reaches the deterministic cost_control composer even with an active LLM" do
      mission = build_mission!
      allow_any_instance_of(described_class)
        .to receive(:diff_from_llm).and_return(llm_scale_proposal)

      cost = double(
        "Signal", kind: "system.project_cost_breach", severity: :medium,
        payload: { "mission_id" => mission.id, "target_usd" => 200.0,
                   "correlation_id" => "project_slo:#{mission.id}:cost" },
        fingerprint: "project_cost_breach:#{mission.id}"
      )

      # Under LLM-first this composed the LLM's ADDITIVE scale_project step —
      # a cost breach answered by growing the fleet. cost_control is
      # deterministic, so the scale-IN composer owns it outright.
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(signals: [ cost ])

      expect(step_inputs(plan)["scaling_strategy"])
        .to eq(described_class::REMOVAL_STRATEGY)
      expect(plan.steps.in_order.first.execution_config["composed_by"]).to eq("deterministic")
    end

    it "still routes operator-only change types to the LLM, stamped as such" do
      mission = build_mission!
      allow_any_instance_of(described_class).to receive(:diff_from_llm).and_return(
        # attach_storage requires instance_id AND size_gb — a proposal
        # missing either is dropped as unbindable.
        [ { "skill" => "attach_storage",
            "inputs" => { "instance_id" => "inst-1", "size_gb" => 10 },
            "on_failure" => "rollback" } ]
      )

      # schema_change is not sensor-derivable — no deterministic composition
      # exists for it, so the LLM remains the composer.
      result = described_class.new(account: account, mission: mission)
        .propose_change(change_type: "schema_change")

      step = result[:plan].steps.in_order.first
      expect(step.execution_config["skill"]).to eq("attach_storage")
      expect(step.execution_config["composed_by"]).to eq("llm")
    end
  end

  # ---------------------------------------------------------------------
  # cost_control cannot bind to an additive-only actuator
  # ---------------------------------------------------------------------
  describe "cost_control composes a bindable scale-IN step" do
    it "shapes the removal to the executor's contract" do
      mission = build_mission!
      cost = double(
        "Signal",
        kind: "system.project_cost_breach",
        severity: :medium,
        payload: {
          "mission_id" => mission.id,
          "observed_usd" => 280.0,
          "target_usd" => 200.0,
          "breach_pct" => 40.0,
          "correlation_id" => "project_slo:#{mission.id}:cost"
        },
        fingerprint: "project_cost_breach:#{mission.id}"
      )

      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(signals: [ cost ])

      # Previously this composed a scale_project step carrying neither
      # project_id nor scaling_strategy — it could only ever fail at
      # execution, so the arm declined instead. INC-4 added remove_replicas and
      # IMP-e68a93c47106 wired the arm to it: the step now carries the whole
      # contract, so it survives #bindable? and can actually run.
      inputs = step_inputs(plan)
      described_class::SCALE_PROJECT_REQUIRED_INPUTS.each do |key|
        expect(inputs[key]).to be_present, "expected the scale-IN step to carry #{key}"
      end
      expect(inputs["scaling_strategy"]).to eq(described_class::REMOVAL_STRATEGY)
    end
  end

  # ---------------------------------------------------------------------
  # A fully-down fleet is the strongest case for scaling out — it must
  # compose, not go silent.
  # ---------------------------------------------------------------------
  describe "a live observation of ZERO" do
    it "composes a scale-out rather than treating 0 as unknown" do
      mission = build_mission!
      plan = described_class.new(account: account, mission: mission)
        .propose_from_signals(
          signals: [ slo_signal(mission: mission, replica_count: 0) ]
        )

      expect(plan).not_to be_nil
      inputs = step_inputs(plan)
      # breach 100 → +2 from an observed 0.
      expect(inputs["desired_replica_count"]).to eq(2)
      expect(inputs["target_count"]).to eq(2)
    end

    it "distinguishes an observed 0 from an absent reading" do
      # 0 composes (above); nil does not. The two must never share a path.
      mission = build_mission!
      expect(
        described_class.new(account: account, mission: mission)
          .propose_from_signals(
            signals: [ slo_signal(mission: mission, replica_count: nil) ]
          )
      ).to be_nil
    end
  end

  # ---------------------------------------------------------------------
  # Decline at compose time when the step provably cannot bind.
  # ---------------------------------------------------------------------
  describe "unresolved compute footprint" do
    it "declines rather than composing an add_replicas step with no template" do
      # No original plan → no template/region/instance-type. auto_apply? only
      # measures the replica ceiling, so composing here would auto-dispatch a
      # step the scaling skill rejects outright.
      mission = build_mission!(with_plan: false)

      expect(
        described_class.new(account: account, mission: mission)
          .propose_from_signals(
            signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
          )
      ).to be_nil
    end

    it "declines when the plan's provision step lacks a region" do
      mission = build_mission!(footprint: original_footprint.except("provider_region_id"))

      expect(
        described_class.new(account: account, mission: mission)
          .propose_from_signals(
            signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
          )
      ).to be_nil
    end
  end

  # ---------------------------------------------------------------------
  # Operator-facing behaviour of the now-actuatable cost_control lane.
  # ---------------------------------------------------------------------
  describe "operator request for cost_control" do
    it "composes a removal rather than raising an unsupported-change-type error" do
      # Was: asserted UnsupportedChangeTypeError naming the missing scale-in
      # strategy. IMP-e68a93c47106 wired the composer, so the refusal is gone
      # and the entry that produced it was deleted with it.
      mission = build_mission!
      result = described_class.new(account: account, mission: mission)
        .propose_change(change_type: "cost_control")

      expect(result[:plan]).not_to be_nil
      expect(step_inputs(result[:plan])["scaling_strategy"])
        .to eq(described_class::REMOVAL_STRATEGY)
      # A removal is never eligible for unattended application, no matter who
      # asked for it.
      expect(result[:auto_apply]).to be false
    end

    it "advertises no change type as unsupported" do
      # A stale "not supported" advertisement is its own defect — an entry here
      # must be deleted in the same commit that composes for it.
      expect(described_class::UNSUPPORTED_CHANGE_TYPES).to be_empty
    end

    it "keeps cost_control requestable so the advertised schema stays stable" do
      expect(described_class::REQUESTABLE_CHANGE_TYPES).to include("cost_control")
    end
  end

  # ---------------------------------------------------------------------
  # Bindability is enforced on EVERY composer path, including the fallback
  # taken when the LLM returns nothing. That fallback is a composer too, and
  # guarding only the LLM branch left it free to emit an unbindable step.
  # ---------------------------------------------------------------------
  describe "the LLM-empty fallback is guarded too" do
    let(:region_drift) do
      double(
        "Signal", kind: "system.project_drift", severity: :medium,
        payload: { "mission_id" => mission_for_fallback.id, "drift_type" => "region_count",
                   "observed" => 1, "target" => 2, "correlation_id" => "fallback" },
        fingerprint: "project_drift:#{mission_for_fallback.id}:region_count"
      )
    end
    let(:mission_for_fallback) { build_mission! }

    it "composes nothing when the fallback's step cannot bind" do
      # region_count drift → relocate → LLM returns nothing → heuristic
      # fallback emits relocate_workload with only target_regions, while the
      # executor declares 8 required inputs. Dispatching that step fails with
      # "missing required input: from_region_id" and mints an approval
      # request plus a RemediationOutcome that can never settle.
      allow_any_instance_of(described_class).to receive(:diff_from_llm).and_return(nil)

      expect(
        described_class.new(account: account, mission: mission_for_fallback)
          .propose_from_signals(signals: [ region_drift ])
      ).to be_nil
    end

    it "composes when the same path yields a step that DOES bind" do
      allow_any_instance_of(described_class).to receive(:diff_from_llm).and_return([
        { "skill" => "relocate_workload",
          "inputs" => { "project_id" => mission_for_fallback.id, "from_region_id" => "r1",
                        "to_region_id" => "r2", "cutover_strategy" => "blue_green",
                        "template_id" => "tmpl-aaa", "provider_instance_type_id" => "itype-ccc",
                        "count" => 2, "source_instance_ids" => %w[i-1] },
          "on_failure" => "rollback" }
      ])

      plan = described_class.new(account: account, mission: mission_for_fallback)
        .propose_from_signals(signals: [ region_drift ])
      expect(plan.steps.in_order.first.execution_config["skill"]).to eq("relocate_workload")
    end
  end

  # ---------------------------------------------------------------------
  # Regression guard: the auto-apply ceiling still reads a real value.
  # ---------------------------------------------------------------------
  describe "auto_apply? ceiling still applies to the converged count" do
    it "keeps desired_replica_count as the policy-facing absolute" do
      mission = build_mission!
      service = described_class.new(account: account, mission: mission)
      plan = service.propose_from_signals(
        signals: [ drift_signal(observed: 1, target: 2, mission: mission) ]
      )

      # ceiling is 8; converged absolute is 2 → within window.
      expect(service.auto_apply?(plan: plan)).to be true
    end
  end
end
