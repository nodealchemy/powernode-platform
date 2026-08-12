# frozen_string_literal: true

require "rails_helper"

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
      "use_case" => "Side business",
      "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
      "regions" => %w[us-east-1 us-west-2 eu-west-1],
      "compliance" => [],
      "budget_cap_usd_monthly" => 200.0,
      "data_residency" => [],
      "preferred_provider" => nil
    }
  end

  let(:slo_targets) do
    {
      "availability_pct" => 99.5,
      "p99_latency_ms" => 250,
      "cost_ceiling_usd" => 200.0
    }
  end

  let(:watch_policies) { { "auto_scale_max_replicas" => 5 } }

  # Production shape: an active infrastructure mission was composed FROM a
  # provisioning plan, and that plan's provision step is where the adaptation
  # composer reads the footprint (template / region / instance type) a
  # scale-out must replicate. Without it the composer declines rather than
  # emitting an add_replicas step the scaling skill would reject, so these
  # fixtures carry the plan a real mission always has.
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
    target.update!(configuration: target.configuration.merge(
      "plan" => { "plan_id" => plan.id }
    ))
    target
  end

  # `let!` so the fixture plan + its goal exist BEFORE any example body runs —
  # otherwise the goal-count assertions would capture this fixture's goal.
  let!(:mission) do
    m = create(
      :ai_mission,
      account: account,
      created_by: user,
      mission_type: "infrastructure",
      custom_phases: [{ "key" => "adapting", "label" => "Adapting", "order" => 0 }],
      configuration: {
        "brief" => default_brief,
        "slo_targets" => slo_targets,
        "watch_policies" => watch_policies
      }
    )
    m.update_columns(status: "active")
    stamp_provisioning_plan!(m.reload)
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  # A synthetic signal class double — avoids loading the system extension's
  # System::Fleet::Signal across slice boundaries (per the patterns memo).
  let(:slo_signal) do
    double(
      "Signal",
      kind: "system.project_slo_violation",
      severity: :high,
      payload: {
        "mission_id" => mission.id,
        "metric" => "p99_latency_ms",
        "observed" => 500.0,
        "target" => 250.0,
        "breach_pct" => 100.0,
        # ProjectSloSensor stamps the observed fleet size onto every SLO
        # violation: `observed` above is the breached METRIC, so the replica
        # count has to ride alongside it. The proposer reads only this — it
        # never substitutes brief.scale.initial for an unobservable fleet.
        "replica_count" => 3,
        "correlation_id" => "project_slo:#{mission.id}:111"
      },
      fingerprint: "project_slo_violation:#{mission.id}:p99_latency_ms"
    )
  end

  let(:cost_signal) do
    double(
      "Signal",
      kind: "system.project_cost_breach",
      severity: :medium,
      payload: {
        "mission_id" => mission.id,
        "observed_usd" => 280.0,
        "target_usd" => 200.0,
        "breach_pct" => 40.0,
        "correlation_id" => "project_slo:#{mission.id}:111"
      },
      fingerprint: "project_cost_breach:#{mission.id}"
    )
  end

  let(:region_drift_signal) do
    double(
      "Signal",
      kind: "system.project_drift",
      severity: :medium,
      payload: {
        "mission_id" => mission.id,
        "drift_type" => "region_count",
        "observed" => 2,
        "target" => 3,
        "correlation_id" => "project_slo:#{mission.id}:111"
      },
      fingerprint: "project_drift:#{mission.id}:region_count"
    )
  end

  before do
    # Default: skip the LLM seam so tests use the heuristic fallback.
    allow_any_instance_of(described_class).to receive(:diff_from_llm).and_return(nil)
  end

  describe "#propose_from_signals" do
    it "returns nil when given an empty signal list" do
      expect(service.propose_from_signals(signals: [])).to be_nil
    end

    it "produces an Ai::GoalPlan with provisioning_skill steps for an SLO violation" do
      plan = service.propose_from_signals(signals: [slo_signal])

      expect(plan).to be_a(Ai::GoalPlan)
      expect(plan.steps).not_to be_empty
      expect(plan.steps.pluck(:step_type)).to all(eq("provisioning_skill"))
    end

    it "selects scale_project as the default skill for SLO-driven scale_horizontal" do
      plan = service.propose_from_signals(signals: [slo_signal])
      first_step = plan.steps.in_order.first

      expect(first_step.execution_config["skill"]).to eq("scale_project")
      expect(first_step.execution_config.dig("inputs", "change_type")).to eq("scale_horizontal")
      expect(first_step.execution_config.dig("inputs", "mission_id")).to eq(mission.id)
      expect(first_step.execution_config["on_failure"]).to eq("rollback")
    end

    it "increases the recommended replica count proportional to breach severity" do
      plan = service.propose_from_signals(signals: [slo_signal])
      desired = plan.steps.in_order.first.execution_config.dig("inputs", "desired_replica_count")
      # initial=3, breach_pct=100 → +2 → 5
      expect(desired).to eq(5)
    end

    it "declines to compose for project_cost_breach while no scale-in strategy exists" do
      # Was: asserted a composed cost_control step carrying target_cost_usd.
      # That step named `scale_project` but carried none of its required
      # kwargs (project_id / target_count / scaling_strategy), so it could
      # only ever fail at execution with "missing required input:
      # project_id" — a cost breach implies scaling IN, and the skill offers
      # only additive strategies. Declining is the correct composition until
      # INC-4 (IMP-216a6dbc7e32) lands `remove_replicas`.
      expect(service.propose_from_signals(signals: [cost_signal])).to be_nil
    end

    it "treats region drift as relocate change_type and emits relocate_workload" do
      plan = service.propose_from_signals(signals: [region_drift_signal])
      first_step = plan.steps.in_order.first
      expect(first_step.execution_config["skill"]).to eq("relocate_workload")
      expect(first_step.execution_config.dig("inputs", "target_regions")).to eq(default_brief["regions"])
    end

    it "carries the signal correlation_id into step inputs" do
      plan = service.propose_from_signals(signals: [slo_signal])
      first_step = plan.steps.in_order.first
      expect(first_step.execution_config.dig("inputs", "correlation_id"))
        .to eq("project_slo:#{mission.id}:111")
    end

    it "creates an Ai::AgentGoal linked to the mission" do
      expect { service.propose_from_signals(signals: [slo_signal]) }
        .to change(Ai::AgentGoal, :count).by(1)
      goal = Ai::AgentGoal.order(:created_at).last
      expect(goal.metadata).to include("provisioning_mission_id" => mission.id, "kind" => "adaptation")
      expect(goal.goal_type).to eq("improvement")
    end

    it "reuses an existing adaptation goal across multiple signals" do
      # Second signal must be one that actually COMPOSES, otherwise the
      # assertion passes trivially without ever reaching find_or_create_goal!
      # — cost_control now declines before that point.
      service.propose_from_signals(signals: [slo_signal])
      expect { service.propose_from_signals(signals: [region_drift_signal]) }
        .not_to change(Ai::AgentGoal, :count)
    end

    it "increments plan version on subsequent proposals" do
      # Second signal is region drift rather than a cost breach: cost_control
      # no longer composes at all (see the decline spec above), so it cannot
      # produce the second plan this assertion needs.
      first = service.propose_from_signals(signals: [slo_signal])
      second = service.propose_from_signals(signals: [region_drift_signal])
      expect(second.version).to eq(first.version + 1)
    end

    it "honors a fixture proposal returned by diff_from_llm when valid" do
      allow_any_instance_of(described_class).to receive(:diff_from_llm).and_return([
        {
          "skill" => "scale_project",
          # A "valid" scale_project proposal must carry the executor's
          # required kwargs — without them the step is dropped as unbindable.
          "inputs" => { "desired_replica_count" => 4, "change_type" => "scale_horizontal",
                        "project_id" => "mission-x", "target_count" => 1,
                        "scaling_strategy" => "add_replicas" },
          "on_failure" => "rollback"
        },
        {
          "skill" => "configure_sdwan_for_project",
          "inputs" => { "regions" => %w[us-east-1 us-west-2] },
          "on_failure" => "continue"
        }
      ])

      # Driven through an operator-only change type: composition is now
      # deterministic-first, so scale_horizontal (and every other
      # sensor-derived change type) never consults the LLM. schema_change has
      # no deterministic composition, so it is where the LLM still composes.
      plan = service.propose_change(change_type: "schema_change")[:plan]
      skills = plan.steps.in_order.pluck(:execution_config).map { |c| c["skill"] }
      expect(skills).to eq(%w[scale_project configure_sdwan_for_project])
    end

    it "sanitizes LLM-suggested skills not in the M2 allowlist" do
      allow_any_instance_of(described_class).to receive(:diff_from_llm).and_return([
        { "skill" => "drop_database", "inputs" => {}, "on_failure" => "rollback" }
      ])

      plan = service.propose_change(change_type: "schema_change")[:plan]
      # Falls back to the heuristic skill list — never invokes drop_database.
      skills = plan.steps.in_order.pluck(:execution_config).map { |c| c["skill"] }
      expect(skills).to eq(["attach_storage"])
    end

    it "routes the resulting plan through ApprovalWorkflowService" do
      approval_double = instance_double(Ai::Autonomy::ApprovalWorkflowService)
      allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:new).and_return(approval_double)
      expect(approval_double).to receive(:request_approval).with(
        hash_including(
          action_type: "project.adapt_scale_horizontal",
          description: include(mission.name)
        )
      )

      service.propose_from_signals(signals: [slo_signal])
    end

    it "requests no approval for a cost_breach, because nothing is composed" do
      # Was: asserted approval routing tagged "project.adapt_cost_control".
      # Approval routing is downstream of composition, so declining to
      # compose (above) necessarily means a cost breach no longer routes.
      # Pinning that consequence explicitly rather than leaving it implied:
      # restoring cost_control actuation in INC-4 must restore this too.
      approval_double = instance_double(Ai::Autonomy::ApprovalWorkflowService)
      allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:new).and_return(approval_double)
      expect(approval_double).not_to receive(:request_approval)

      expect(service.propose_from_signals(signals: [cost_signal])).to be_nil
    end

    it "swallows exceptions and returns nil when persistence fails" do
      allow(Ai::GoalPlan).to receive(:create!).and_raise(StandardError, "boom")
      expect(service.propose_from_signals(signals: [slo_signal])).to be_nil
    end

    it "selects the highest-severity signal as primary when multiple are passed" do
      plan = service.propose_from_signals(signals: [cost_signal, slo_signal])
      # slo_signal has :high severity vs :medium for cost_signal.
      first_step = plan.steps.in_order.first
      expect(first_step.execution_config.dig("inputs", "change_type")).to eq("scale_horizontal")
    end
  end

  describe "#propose_from_signals with LLM proposals" do
    # Synthetic LLM response value object — keeps stubbing self-contained
    # without requiring OpenStruct or coupling to the real WorkerLlmClient
    # response type. Struct member named `status` because Struct rejects
    # member names containing `?`; `success?` is aliased on top.
    let(:llm_response_class) do
      Struct.new(:status, :content, keyword_init: true) do
        def success?
          status
        end
      end
    end

    # Synthetic LLM client that records calls and returns a queued response.
    # Satisfies the contract used by AdaptationProposerService#safe_complete:
    # `client.complete(model:, **opts)` returning an object with `.success?`
    # and `.content`.
    let(:fake_llm_client) do
      Class.new do
        attr_accessor :next_response, :calls

        def initialize
          @calls = []
        end

        def complete(**opts)
          @calls << opts
          @next_response
        end
      end.new
    end

    before do
      # Override the file-wide nil stub so the real diff_from_llm runs and
      # exercises parse_diff_json + sanitize_steps end-to-end. Inject the
      # synthetic client at the public llm_client seam — same shape as
      # WorkerLlmClient but no provider plumbing.
      allow_any_instance_of(described_class).to receive(:diff_from_llm).and_call_original
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(fake_llm_client)
    end

    # Composition is deterministic-first: every sensor-derived change type is
    # composed without consulting the LLM. These examples therefore drive
    # `schema_change` — an operator-only change type with no deterministic
    # composition — which is the lane where the LLM is still the composer.
    # Its heuristic fallback skill is `attach_storage`.
    def llm_composed_plan
      service.propose_change(change_type: "schema_change")[:plan]
    end

    it "produces a diff plan when the LLM returns a valid scale_project step" do
      fake_llm_client.next_response = llm_response_class.new(
        status: true,
        content: <<~JSON
          [
            {
              "skill": "scale_project",
              "inputs": { "desired_replica_count": 6, "change_type": "scale_horizontal",
                          "project_id": "mission-x", "target_count": 2,
                          "scaling_strategy": "add_replicas" },
              "on_failure": "rollback"
            }
          ]
        JSON
      )

      plan = llm_composed_plan

      expect(plan).to be_a(Ai::GoalPlan)
      first = plan.steps.in_order.first
      expect(first.execution_config["skill"]).to eq("scale_project")
      expect(first.execution_config.dig("inputs", "desired_replica_count")).to eq(6)
      expect(first.execution_config["on_failure"]).to eq("rollback")
      expect(fake_llm_client.calls.size).to eq(1)
    end

    it "drops LLM-suggested skills outside the M2 allowlist and falls back to the heuristic" do
      fake_llm_client.next_response = llm_response_class.new(
        status: true,
        content: '[{"skill": "drop_database", "inputs": {}, "on_failure": "rollback"}]'
      )

      plan = llm_composed_plan
      skills = plan.steps.in_order.pluck(:execution_config).map { |c| c["skill"] }
      # `drop_database` is not in ADAPTATION_SKILLS — sanitize_steps drops it,
      # the array is empty, build_steps_for falls through to heuristic_steps.
      expect(skills).to eq(["attach_storage"])
    end

    it "rescues malformed JSON, logs a warning, and falls back to the heuristic" do
      fake_llm_client.next_response = llm_response_class.new(
        status: true,
        # Has `[` and `]` so parse_diff_json reaches JSON.parse, but contents
        # are invalid → JSON::ParserError is rescued and logged.
        content: '[{"skill": "scale_project", "inputs":}]'
      )

      allow(Rails.logger).to receive(:warn).and_call_original

      plan = llm_composed_plan

      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/diff JSON parse failed/))
      expect(plan).to be_a(Ai::GoalPlan)
      expect(plan.steps.in_order.first.execution_config["skill"]).to eq("attach_storage")
    end

    it "does NOT enforce mission.brief budget_cap_usd_monthly at this layer" do
      # Documents the contract: AdaptationProposerService passes through the
      # LLM-proposed step verbatim — cost-cap enforcement is a downstream
      # concern (operator approval policy resolver + ApprovalWorkflowService).
      # Pinning this so a future refactor that moves enforcement upstream is
      # an intentional decision rather than incidental.
      #
      # Uses attach_storage rather than scale_project: an expensive step still
      # passes through, but a scale_project step is additionally required to
      # carry its executor's kwargs (see the guard example below), so it would
      # confound the two contracts.
      expect(default_brief["budget_cap_usd_monthly"]).to eq(200.0)

      fake_llm_client.next_response = llm_response_class.new(
        status: true,
        content: <<~JSON
          [{
            "skill": "attach_storage",
            "inputs": { "size_gb": 100, "estimated_cost_usd_monthly": 10000 },
            "on_failure": "rollback"
          }]
        JSON
      )

      plan = llm_composed_plan
      inputs = plan.steps.in_order.first.execution_config["inputs"]
      expect(inputs["size_gb"]).to eq(100)
      expect(inputs["estimated_cost_usd_monthly"]).to eq(10000)
    end

    it "DROPS an LLM scale_project step that lacks the executor's required kwargs" do
      # The allowlist validates the skill slug only, so without this guard an
      # LLM-composed scale_project ships with no project_id / target_count /
      # scaling_strategy and dies at execution with "missing required input:
      # project_id" — the exact failure the deterministic-first inversion
      # removed from the sensor lanes. The guard applies to ANY composed
      # scale_project step, whichever composer produced it.
      fake_llm_client.next_response = llm_response_class.new(
        status: true,
        content: <<~JSON
          [{
            "skill": "scale_project",
            "inputs": { "desired_replica_count": 100 },
            "on_failure": "rollback"
          }]
        JSON
      )

      plan = llm_composed_plan
      skills = plan.steps.in_order.pluck(:execution_config).map { |c| c["skill"] }
      # Dropped, so the diff falls through to a composition that binds.
      expect(skills).not_to include("scale_project")
      expect(skills).to eq(["attach_storage"])
    end

    it "KEEPS an LLM scale_project step that does carry them" do
      fake_llm_client.next_response = llm_response_class.new(
        status: true,
        content: <<~JSON
          [{
            "skill": "scale_project",
            "inputs": { "project_id": "mission-x", "target_count": 2,
                        "scaling_strategy": "add_replicas" },
            "on_failure": "rollback"
          }]
        JSON
      )

      plan = llm_composed_plan
      expect(plan.steps.in_order.first.execution_config["skill"]).to eq("scale_project")
    end

    it "preserves the LLM-suggested skill verbatim while action_type derives from the signal" do
      # action_type = "project.adapt_#{change_type}", and change_type comes
      # from derive_change_type(signal) — NOT the LLM-chosen skill. A
      # region_drift signal yields change_type=relocate → action_type=
      # project.adapt_relocate, regardless of which allowlisted skill the
      # LLM picks. The LLM's skill choice is what the executor will run.
      fake_llm_client.next_response = llm_response_class.new(
        status: true,
        content: <<~JSON
          [{
            "skill": "relocate_workload",
            "inputs": { "target_regions": ["us-east-1", "eu-west-1"] },
            "on_failure": "rollback"
          }]
        JSON
      )

      approval_double = instance_double(Ai::Autonomy::ApprovalWorkflowService)
      allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:new).and_return(approval_double)
      expect(approval_double).to receive(:request_approval).with(
        hash_including(action_type: "project.adapt_relocate")
      )

      plan = service.propose_from_signals(signals: [region_drift_signal])
      expect(plan.steps.in_order.first.execution_config["skill"]).to eq("relocate_workload")
    end

    it "does not invoke the LLM when the signal list is empty" do
      call_count = 0
      allow_any_instance_of(described_class).to receive(:diff_from_llm) do
        call_count += 1
        nil
      end

      expect(service.propose_from_signals(signals: [])).to be_nil
      expect(call_count).to eq(0)
    end

    it "preserves correlation_id from the sensor signal in LLM-proposed step inputs" do
      # decorate_with_signal_metadata! mirrors the heuristic path's behavior:
      # the LLM may omit correlation_id from its proposal, but downstream
      # skill executors require it to correlate the action with the alert,
      # so the proposer injects it from the signal payload.
      fake_llm_client.next_response = llm_response_class.new(
        status: true,
        content: <<~JSON
          [{
            "skill": "scale_project",
            "inputs": { "desired_replica_count": 5, "change_type": "scale_horizontal" },
            "on_failure": "rollback"
          }]
        JSON
      )

      plan = service.propose_from_signals(signals: [slo_signal])
      inputs = plan.steps.in_order.first.execution_config["inputs"]
      expect(inputs["correlation_id"]).to eq("project_slo:#{mission.id}:111")
    end

    it "treats an unsuccessful LLM response (success? == false) as a miss and falls back" do
      fake_llm_client.next_response = llm_response_class.new(status: false, content: nil)

      plan = service.propose_from_signals(signals: [slo_signal])
      first_step = plan.steps.in_order.first
      expect(first_step.execution_config["skill"]).to eq("scale_project")
      expect(first_step.execution_config.dig("inputs", "desired_replica_count")).to eq(5)
    end
  end

  describe "#auto_apply?" do
    it "returns true when scale_project replica count is within auto-scale ceiling" do
      plan = service.propose_from_signals(signals: [slo_signal])
      # initial=3, breach_pct=100 → desired=5; ceiling=5 → within window.
      expect(service.auto_apply?(plan: plan)).to be true
    end

    it "returns false when desired replica count exceeds the ceiling" do
      mission.update!(configuration: mission.configuration.merge(
        "watch_policies" => { "auto_scale_max_replicas" => 4 }
      ))
      plan = described_class.new(account: account, mission: mission.reload)
        .propose_from_signals(signals: [slo_signal])
      expect(described_class.new(account: account, mission: mission).auto_apply?(plan: plan)).to be false
    end

    it "returns false when no auto_scale_max_replicas policy exists" do
      mission.update!(configuration: mission.configuration.merge("watch_policies" => {}))
      plan = described_class.new(account: account, mission: mission.reload)
        .propose_from_signals(signals: [slo_signal])
      expect(described_class.new(account: account, mission: mission).auto_apply?(plan: plan)).to be false
    end

    it "returns false for relocate plans regardless of replica count" do
      plan = service.propose_from_signals(signals: [region_drift_signal])
      expect(service.auto_apply?(plan: plan)).to be false
    end

    it "returns false for nil plans" do
      expect(service.auto_apply?(plan: nil)).to be false
    end
  end

  describe "constants" do
    it "exposes a stable ADAPTATION_SKILLS allowlist" do
      expect(described_class::ADAPTATION_SKILLS).to eq(%w[
        scale_project
        relocate_workload
        attach_storage
        configure_sdwan_for_project
      ])
    end

    it "exposes CHANGE_TYPES mapping each project signal kind" do
      expect(described_class::CHANGE_TYPES.keys).to include(
        "system.project_slo_violation",
        "system.project_drift",
        "system.project_cost_breach"
      )
    end
  end
end
