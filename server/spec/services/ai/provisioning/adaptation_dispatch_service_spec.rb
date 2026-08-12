# frozen_string_literal: true

require "rails_helper"

# IMP-8c37b9e5ccd5 (INC-2) — `adaptation_diff` plans were WRITTEN AND NEVER
# READ. AdaptationProposerService composed a diff-shaped Ai::GoalPlan, left it
# in `draft`, and nothing anywhere dispatched it: the mission's live plan never
# grew the steps, the runner never saw them, the verify phase never re-ran, and
# the RemediationOutcome the fleet validator scores was never minted. The whole
# adaptive-evolution lane terminated in a persisted record.
#
# This spec covers the consumer:
#
#   GATE      — the plan is dispatched ONLY through the `adaptation_gate`
#               registry seam. Absent seam (core mode), an erroring seam, or a
#               seam that tries to widen core's bounds all PARK the plan in
#               draft. There is no silent proceed.
#   APPEND    — cleared steps are appended onto the mission's LIVE plan (the
#               one `mission.configuration.plan.plan_id` names) rather than run
#               out of the diff plan, because that live plan is what
#               VerificationService reads. Step numbers continue past the
#               existing maximum and intra-diff dependencies are remapped.
#   DISPATCH  — only the appended steps are dispatched. `execute!` refuses to
#               run a plan any of whose steps is past `pending`, and a live
#               plan's original steps are all `completed`, so the ordinary
#               entrypoint would no-op every adaptation.
#   SETTLE    — once the appended steps complete, VerificationService re-runs
#               against the ADAPTED plan and, only when it comes back healthy,
#               a pending RemediationOutcome is recorded through the seam. The
#               fleet validator flips it to effective on fingerprint clear.
RSpec.describe Ai::Provisioning::AdaptationDispatchService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, status: "active") }

  let(:goal) do
    Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Goal", goal_type: "improvement",
      status: "pending", priority: 3, progress: 0.0, success_criteria: {}, metadata: {}
    )
  end

  # The mission's LIVE plan — two completed provisioning steps, exactly the
  # shape an adaptation lands on. Their `completed` status is load-bearing: it
  # is what makes SkillCompositionRunner#execute! a no-op.
  let(:live_plan) do
    plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                                status: "executing", version: 1,
                                plan_data: { "kind" => "provisioning" })
    plan.steps.create!(
      step_number: 1, step_type: "provisioning_skill", status: "completed",
      description: "provision", dependencies: [],
      execution_config: { "skill" => "provision_full_stack", "on_failure" => "rollback",
                          "inputs" => { "count" => 2, "provider_region_id" => "region-1",
                                        "template_id" => "tmpl-1" } },
      metadata: { "last_outputs" => { "outputs" => { "node_instance_ids" => %w[i-1 i-2] },
                                      "failures" => [] } }
    )
    plan
  end

  # The real system_provisioning phase list. `adapting` is where a mission
  # LIVES while it is being adapted — it left `execute` long ago — and that is
  # exactly why the runner must not treat a completed adaptation as an
  # execute-phase advance.
  let!(:provisioning_template) do
    ::Ai::MissionTemplate.find_or_create_by!(name: "system_provisioning", template_type: "system") do |t|
      t.account = nil
      t.description = "test fixture"
      t.mission_type = "infrastructure"
      t.status = "active"
      t.is_default = true
      t.version = 1
      t.phases = %w[capture_intent compose_plan review_plan execute verify handoff adapting]
        .each_with_index.map do |key, idx|
          { "order" => idx, "key" => key, "label" => key.titleize,
            "requires_approval" => %w[review_plan handoff].include?(key) }
        end
      t.approval_gates = %w[review_plan handoff]
      t.rejection_mappings = {}
      t.skill_compositions = {}
      t.default_configuration = {}
    end
  end

  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        mission_template: provisioning_template,
                        current_phase: "adapting",
                        configuration: {
                          "plan" => { "plan_id" => live_plan.id },
                          "watch_policies" => { "auto_scale_max_replicas" => 8 }
                        })
  end

  # A diff plan of the exact shape AdaptationProposerService persists.
  def build_diff_plan!(steps: nil, fingerprint: "slo:mission:p99", change_type: "scale_horizontal")
    steps ||= [
      { "skill" => "scale_project", "on_failure" => "rollback", "composed_by" => "deterministic",
        "inputs" => { "mission_id" => mission.id, "change_type" => "scale_horizontal",
                      "desired_replica_count" => 4, "project_id" => mission.id,
                      "target_count" => 2, "scaling_strategy" => "add_replicas",
                      "template_id" => "tmpl-1", "provider_region_id" => "region-1",
                      "provider_instance_type_id" => "itype-1" } }
    ]

    plan_data = {
      "kind" => "adaptation_diff", "change_type" => change_type,
      "signal_kind" => "system.project_slo_violation",
      "signal_payload" => { "_sensor" => "ProjectSloSensor", "correlation_id" => "corr-1" },
      "mission_id" => mission.id
    }
    plan_data["signal_fingerprint"] = fingerprint if fingerprint

    plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                                status: "draft", version: 2, plan_data: plan_data)
    steps.each_with_index do |attrs, idx|
      plan.steps.create!(
        step_number: idx + 1, step_type: "provisioning_skill", status: "pending",
        description: "Scale project", execution_config: attrs,
        dependencies: idx.zero? ? [] : [ idx ]
      )
    end
    plan
  end

  # ONE base stub for the registry, established before any example adds a
  # per-key constraint. A later unconstrained `receive(:provider)` replaces every
  # prior expectation for that message, so re-declaring the base inside each
  # helper silently dropped whichever constraint was registered first — which is
  # how the real System::ProvisionVerifier ended up answering a settle spec.
  before { allow(::Powernode::ExtensionRegistry).to receive(:provider).and_call_original }

  def stub_gate(gate)
    allow(::Powernode::ExtensionRegistry).to receive(:provider)
      .with(:adaptation_gate).and_return(gate)
  end

  # The system extension IS loaded in this suite, so `provision_verifier`
  # resolves to the real System::ProvisionVerifier and fails every fixture
  # instance id. The settle path's subject is the RE-RUN and what it gates, not
  # provider reconciliation (verification_service_spec owns that), so stand in a
  # reconciler that confirms whatever it is asked about.
  def stub_confirming_verifier
    reconciler = double("provision_verifier")
    allow(reconciler).to receive(:reconcile_instances) do |account:, expectations:|
      expectations.map do |e|
        { node_instance_id: e[:node_instance_id], ok: true, detail: "provider reports running" }
      end
    end
    allow(::Powernode::ExtensionRegistry).to receive(:provider)
      .with(:provision_verifier).and_return(reconciler)
    reconciler
  end


  # A gate that answers exactly the contract core declares.
  def gate_answering(disposition, approval_request_id: nil, capture: nil, authority: nil)
    double("adaptation_gate").tap do |g|
      allow(g).to receive(:adaptation_disposition) do |**kwargs|
        capture&.call(kwargs)
        { disposition: disposition, approval_request_id: approval_request_id,
          authority: authority }.compact
      end
      allow(g).to receive(:record_adaptation_outcome!).and_return(nil)
    end
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  # ---------------------------------------------------------------- gate ----

  describe "#dispatch! gate resolution" do
    before { allow(WorkerJobService).to receive(:enqueue_job).and_return(true) }

    it "PARKS the plan in draft when no adaptation_gate is registered (core mode)" do
      stub_gate(nil)
      plan = build_diff_plan!

      result = service.dispatch!(plan: plan)

      expect(result[:gate]).to eq(described_class::GATE_PARKED)
      expect(result[:dispatched]).to be false
      # Ground truth: nothing moved. The plan is still draft, the live plan did
      # not grow a single step, and no step job was enqueued.
      expect(plan.reload.status).to eq("draft")
      expect(live_plan.reload.steps.count).to eq(1)
      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end

    it "PARKS when the registered gate raises — fail-closed, never a silent proceed" do
      exploding = double("adaptation_gate")
      allow(exploding).to receive(:adaptation_disposition).and_raise(RuntimeError, "policy store down")
      stub_gate(exploding)
      plan = build_diff_plan!

      result = service.dispatch!(plan: plan)

      expect(result[:gate]).to eq(described_class::GATE_PARKED)
      expect(result[:dispatched]).to be false
      expect(result[:detail]).to match(/RuntimeError|policy store down/)
      expect(plan.reload.status).to eq("draft")
      expect(live_plan.reload.steps.count).to eq(1)
    end

    it "PARKS when the registered gate cannot answer the contract at all" do
      stub_gate(double("stale_provider"))
      plan = build_diff_plan!

      result = service.dispatch!(plan: plan)

      expect(result[:gate]).to eq(described_class::GATE_PARKED)
      expect(plan.reload.status).to eq("draft")
      expect(live_plan.reload.steps.count).to eq(1)
    end

    it "leaves a ROUTED plan in draft with the approval request id surfaced" do
      request_id = SecureRandom.uuid
      stub_gate(gate_answering("routed", approval_request_id: request_id))
      plan = build_diff_plan!

      result = service.dispatch!(plan: plan)

      expect(result[:gate]).to eq(described_class::GATE_ROUTED)
      expect(result[:approval_request_id]).to eq(request_id)
      expect(result[:dispatched]).to be false
      expect(plan.reload.status).to eq("draft")
      expect(live_plan.reload.steps.count).to eq(1)
    end

    it "hands the gate core's bounds verdict, and the gate is the only thing that grants auto-apply" do
      captured = nil
      stub_gate(gate_answering("routed", capture: ->(kw) { captured = kw }))
      plan = build_diff_plan!

      service.dispatch!(plan: plan)

      expect(captured[:auto_apply_eligible]).to be true
      expect(captured[:change_type]).to eq("scale_horizontal")
      expect(captured[:mission].id).to eq(mission.id)
      expect(captured[:plan].id).to eq(plan.id)
    end

    it "passes auto_apply_eligible=false for an out-of-bounds plan" do
      captured = nil
      stub_gate(gate_answering("routed", capture: ->(kw) { captured = kw }))
      # 40 replicas against an auto_scale_max_replicas of 8.
      plan = build_diff_plan!(steps: [
        { "skill" => "scale_project", "on_failure" => "rollback",
          "inputs" => { "change_type" => "scale_horizontal", "desired_replica_count" => 40,
                        "project_id" => mission.id, "target_count" => 38,
                        "scaling_strategy" => "add_replicas" } }
      ])

      service.dispatch!(plan: plan)

      expect(captured[:auto_apply_eligible]).to be false
    end

    it "REFUSES to dispatch when the gate widens core's bounds — a gate may narrow, never widen" do
      stub_gate(gate_answering("auto_apply_within_bounds"))
      plan = build_diff_plan!(steps: [
        { "skill" => "scale_project", "on_failure" => "rollback",
          "inputs" => { "change_type" => "scale_horizontal", "desired_replica_count" => 40,
                        "project_id" => mission.id, "target_count" => 38,
                        "scaling_strategy" => "add_replicas" } }
      ])

      result = service.dispatch!(plan: plan)

      expect(result[:gate]).to eq(described_class::GATE_PARKED)
      expect(result[:dispatched]).to be false
      expect(plan.reload.status).to eq("draft")
      expect(live_plan.reload.steps.count).to eq(1)
    end

    it "DOES apply an out-of-bounds plan a person approved — bounds gate the machine, not the operator" do
      allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
      request_id = SecureRandom.uuid
      stub_gate(gate_answering("auto_apply_within_bounds",
                               approval_request_id: request_id, authority: "approval"))
      plan = build_diff_plan!(steps: [
        { "skill" => "scale_project", "on_failure" => "rollback",
          "inputs" => { "change_type" => "scale_horizontal", "desired_replica_count" => 40,
                        "project_id" => mission.id, "target_count" => 38,
                        "scaling_strategy" => "add_replicas" } }
      ])

      result = service.dispatch!(plan: plan)

      expect(result[:gate]).to eq(described_class::GATE_AUTO_APPLY)
      expect(result[:dispatched]).to be true
      # Nothing is hidden: the envelope still reports the plan as out of bounds.
      expect(result[:within_bounds]).to be false
      expect(result[:approval_request_id]).to eq(request_id)
      expect(live_plan.reload.steps.count).to eq(2)
    end

    it "refuses a plan that is not an adaptation_diff" do
      stub_gate(gate_answering("auto_apply_within_bounds"))
      foreign = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "draft",
                                     version: 3, plan_data: { "kind" => "provisioning" })

      expect { service.dispatch!(plan: foreign) }
        .to raise_error(described_class::NotAnAdaptationPlanError)
    end
  end

  # ------------------------------------------------------- append/dispatch ---

  describe "#dispatch! append + dispatch" do
    before { allow(WorkerJobService).to receive(:enqueue_job).and_return(true) }

    it "appends the diff steps onto the LIVE plan and dispatches only those" do
      stub_gate(gate_answering("auto_apply_within_bounds"))
      plan = build_diff_plan!

      result = service.dispatch!(plan: plan)

      expect(result[:gate]).to eq(described_class::GATE_AUTO_APPLY)
      expect(result[:dispatched]).to be true

      live_plan.reload
      expect(live_plan.steps.count).to eq(2)
      appended = live_plan.steps.order(:step_number).last
      # Numbering continues past the live plan's existing maximum.
      expect(appended.step_number).to eq(2)
      expect(appended.status).to eq("pending")
      expect(appended.execution_config["skill"]).to eq("scale_project")
      expect(appended.execution_config["inputs"]["target_count"]).to eq(2)
      # Provenance back to the proposal — this is what the runner reads to know
      # the DAG completion is an adaptation settle rather than an execute-phase
      # advance.
      expect(appended.execution_config["adapted_from_plan_id"]).to eq(plan.id)

      # The diff plan itself leaves `draft`, which is what releases the
      # DecisionEngine's one-open-proposal-per-mission brake.
      expect(plan.reload.status).to eq("executing")

      # Exactly ONE step job, for the appended step — never for the completed
      # original.
      expect(WorkerJobService).to have_received(:enqueue_job)
        .with("AiProvisioningStepJob", hash_including(args: hash_including(step_id: appended.id)))
        .once
      expect(WorkerJobService).to have_received(:enqueue_job).once
    end

    it "remaps intra-diff dependencies onto the appended step numbers" do
      # A scale + storage adaptation is out of core's auto-apply bounds by
      # construction (the bounds check is an allowlist of the one additive
      # scale-out shape), so it reaches the runner only via a person's
      # approval — which is exactly how a multi-step adaptation gets applied.
      stub_gate(gate_answering("auto_apply_within_bounds",
                               approval_request_id: SecureRandom.uuid,
                               authority: "approval"))
      plan = build_diff_plan!(steps: [
        { "skill" => "scale_project", "on_failure" => "rollback",
          "inputs" => { "change_type" => "scale_horizontal", "desired_replica_count" => 4,
                        "project_id" => mission.id, "target_count" => 2,
                        "scaling_strategy" => "add_replicas" } },
        { "skill" => "attach_storage", "on_failure" => "rollback",
          "inputs" => { "mission_id" => mission.id } }
      ])

      service.dispatch!(plan: plan)

      appended = live_plan.reload.steps.order(:step_number).to_a.last(2)
      expect(appended.map(&:step_number)).to eq([ 2, 3 ])
      # The diff's second step declared dependencies [1] (its own first step);
      # after the append that must point at step 2, not at the live plan's
      # unrelated original step 1.
      expect(appended.first.dependencies).to eq([])
      expect(appended.last.dependencies).to eq([ 2 ])

      # Only the first appended layer dispatches; the dependent step waits.
      expect(WorkerJobService).to have_received(:enqueue_job)
        .with("AiProvisioningStepJob", hash_including(args: hash_including(step_id: appended.first.id)))
        .once
      expect(WorkerJobService).to have_received(:enqueue_job).once
    end

    it "REFUSES to append the same adaptation twice — no double provision" do
      # #dispatch! is deliberately re-callable (that is how a routed plan is
      # released once its approval lands), and once the gate says yes it keeps
      # saying yes. Without a guard the second call appends the same steps
      # again and provisions the replicas twice.
      stub_gate(gate_answering("auto_apply_within_bounds"))
      plan = build_diff_plan!

      first = service.dispatch!(plan: plan)
      second = service.dispatch!(plan: plan.reload)

      expect(first[:dispatched]).to be true
      expect(second[:gate]).to eq(described_class::GATE_ALREADY_APPLIED)
      expect(second[:dispatched]).to be false
      expect(second[:detail]).to match(/already applied/i)
      # Ground truth: one appended step, one step job. Not two. The step is
      # still `pending` here — no worker has picked it up — so status alone
      # cannot tell this from a failed dispatch; the recorded enqueue can.
      expect(live_plan.reload.steps.count).to eq(2)
      expect(WorkerJobService).to have_received(:enqueue_job).once
    end

    # GATE_PARKED's shipped meaning is "the plan stays in draft and NOTHING
    # ran". Once steps are appended that is false, and a confident lie is worse
    # than the ambiguous envelope this task set out to remove.
    it "does NOT report parked when the append succeeded but the dispatch failed" do
      stub_gate(gate_answering("auto_apply_within_bounds"))
      allow(WorkerJobService).to receive(:enqueue_job).and_raise(RuntimeError, "redis down")
      plan = build_diff_plan!

      result = service.dispatch!(plan: plan)

      expect(result[:gate]).to eq(described_class::GATE_APPLIED_DISPATCH_FAILED)
      expect(result[:dispatched]).to be false
      expect(result[:detail]).to match(/redis down|RuntimeError/)
      # Ground truth backing the disposition: the steps really are on the plan.
      expect(live_plan.reload.steps.count).to eq(2)
    end

    it "reports parked when the append itself failed — there, nothing did run" do
      stub_gate(gate_answering("auto_apply_within_bounds"))
      allow_any_instance_of(Ai::GoalPlan).to receive(:steps).and_call_original
      plan = build_diff_plan!
      allow(service).to receive(:append_steps!).and_raise(RuntimeError, "db blip")

      result = service.dispatch!(plan: plan)

      expect(result[:gate]).to eq(described_class::GATE_PARKED)
      expect(result[:dispatched]).to be false
      expect(live_plan.reload.steps.count).to eq(1)
    end

    # The double-append guard must key on STATE, not existence. Appended rows
    # that were never enqueued are the exact residue of a failed dispatch, and
    # refusing them stranded them as `pending` forever — which then blocked
    # every future adaptation on the mission from settling.
    it "RE-DISPATCHES appended steps that were never enqueued" do
      stub_gate(gate_answering("auto_apply_within_bounds"))
      allow(WorkerJobService).to receive(:enqueue_job).and_raise(RuntimeError, "redis down")
      plan = build_diff_plan!
      service.dispatch!(plan: plan)
      expect(live_plan.reload.steps.count).to eq(2)

      # Count only what the RETRY enqueues — the first call's raising
      # invocation is still "received" by the spy and would mask the result.
      enqueued = []
      allow(WorkerJobService).to receive(:enqueue_job) { |*args| enqueued << args; true }
      retried = service.dispatch!(plan: plan.reload)

      expect(retried[:gate]).to eq(described_class::GATE_AUTO_APPLY)
      expect(retried[:dispatched]).to be true
      # Re-dispatched, NOT re-appended.
      expect(live_plan.reload.steps.count).to eq(2)
      expect(enqueued.size).to eq(1)
      expect(enqueued.first.first).to eq("AiProvisioningStepJob")
    end

    it "still REFUSES when an appended step is already past pending" do
      stub_gate(gate_answering("auto_apply_within_bounds"))
      plan = build_diff_plan!
      service.dispatch!(plan: plan)
      live_plan.reload.steps.where(status: "pending").update_all(status: "executing")

      second = service.dispatch!(plan: plan.reload)

      expect(second[:dispatched]).to be false
      expect(second[:detail]).to match(/already applied/i)
      expect(live_plan.reload.steps.count).to eq(2)
      expect(WorkerJobService).to have_received(:enqueue_job).once
    end

    it "parks rather than dispatching when the mission has no live plan to append onto" do
      stub_gate(gate_answering("auto_apply_within_bounds"))
      mission.update!(configuration: mission.configuration.except("plan"))
      plan = build_diff_plan!

      result = service.dispatch!(plan: plan)

      expect(result[:dispatched]).to be false
      expect(plan.reload.status).to eq("draft")
      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end
  end

  # -------------------------------------------------------------- settle ----

  describe "#settle!" do
    before do
      allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
      stub_confirming_verifier
    end

    def dispatch_and_complete!(fingerprint: "slo:mission:p99")
      plan = build_diff_plan!(fingerprint: fingerprint)
      service.dispatch!(plan: plan)
      live_plan.reload.steps.where(status: "pending").find_each do |s|
        s.update!(status: "completed",
                  metadata: { "last_outputs" => { "outputs" => { "node_instance_ids" => %w[i-3 i-4] },
                                                  "failures" => [] } })
      end
      plan
    end

    it "re-runs VerificationService against the ADAPTED live plan and records a pending outcome" do
      recorded = nil
      gate = gate_answering("auto_apply_within_bounds")
      allow(gate).to receive(:record_adaptation_outcome!) { |**kw| recorded = kw }
      stub_gate(gate)

      plan = dispatch_and_complete!

      result = service.settle!(adaptation_plan_ids: [ plan.id ])

      expect(result[:healthy]).to be true
      # The verification must have SEEN the appended step: its count check
      # reads the adaptation's `target_count` (2) against the 2 instance ids it
      # produced. If the re-run had used the pre-adaptation plan, or read only
      # `count`, this would be a failing check.
      names = result[:checks].map { |c| c[:name] }
      expect(names).to include("step_2_status", "step_2_count")
      expect(result[:checks].find { |c| c[:name] == "step_2_count" }[:ok]).to be true

      expect(recorded).to be_present
      expect(recorded[:fingerprint]).to eq("slo:mission:p99")
      expect(recorded[:signal_kind]).to eq("system.project_slo_violation")
      expect(recorded[:mission].id).to eq(mission.id)

      expect(plan.reload.status).to eq("completed")
    end

    it "does not re-settle an adaptation that already settled" do
      recorded = 0
      gate = gate_answering("auto_apply_within_bounds")
      allow(gate).to receive(:record_adaptation_outcome!) { recorded += 1 }
      stub_gate(gate)

      plan = dispatch_and_complete!
      service.settle!(adaptation_plan_ids: [ plan.id ])

      # The appended steps keep their provenance forever, so a LATER
      # adaptation's DAG completion hands this plan id back again. Re-settling
      # would re-mint an outcome once the first had been scored out of pending.
      second = service.settle!(adaptation_plan_ids: [ plan.id ])

      expect(second[:verified]).to be false
      expect(recorded).to eq(1)
    end

    it "scores the adaptation on ITS OWN steps, not on a pre-existing dead instance" do
      # The commonest trigger for a replica scale-out is an instance dying. That
      # dead original still fails live reconciliation afterwards, so scoring the
      # adaptation on the WHOLE plan marked every such remediation failed and
      # minted no outcome — the loop could never record a success in the exact
      # case it exists for.
      recorded = nil
      gate = gate_answering("auto_apply_within_bounds")
      allow(gate).to receive(:record_adaptation_outcome!) { |**kw| recorded = kw }
      stub_gate(gate)

      reconciler = double("provision_verifier")
      allow(reconciler).to receive(:reconcile_instances) do |account:, expectations:|
        expectations.map do |e|
          dead = e[:node_instance_id] == "i-1"
          { node_instance_id: e[:node_instance_id], ok: !dead,
            detail: dead ? "provider reports terminated" : "running" }
        end
      end
      allow(::Powernode::ExtensionRegistry).to receive(:provider)
        .with(:provision_verifier).and_return(reconciler)

      plan = dispatch_and_complete!

      result = service.settle!(adaptation_plan_ids: [ plan.id ])

      # The dead original is still REPORTED — nothing is hidden.
      expect(result[:checks].find { |c| c[:name] == "instance_i-1" }[:ok]).to be false
      # But the adaptation itself landed, so it is scored and recorded.
      expect(result[:healthy]).to be true
      expect(plan.reload.status).to eq("completed")
      expect(recorded).to be_present
    end

    it "settles a FAILED adaptation instead of leaving it executing forever" do
      gate = gate_answering("auto_apply_within_bounds")
      stub_gate(gate)

      plan = build_diff_plan!
      service.dispatch!(plan: plan)
      live_plan.reload.steps.where(status: "pending").find_each do |s|
        s.update!(status: "failed", metadata: { "last_outputs" => {} })
      end

      result = service.settle!(adaptation_plan_ids: [ plan.id ])

      expect(result[:healthy]).to be false
      expect(plan.reload.status).to eq("failed")
      expect(gate).not_to have_received(:record_adaptation_outcome!)
    end

    it "mirrors the settled status onto the diff plan's own proposal steps" do
      stub_gate(gate_answering("auto_apply_within_bounds"))
      plan = dispatch_and_complete!

      service.settle!(adaptation_plan_ids: [ plan.id ])

      # A completed plan whose own steps still read `pending` reports 0% progress.
      expect(plan.reload.steps.pluck(:status)).to all(eq("completed"))
    end

    # The settle scores the adaptation on its own steps so a pre-existing dead
    # instance cannot fail it. But a check that names NOTHING in particular is
    # not someone else's problem — it is a global blocker, and dropping it
    # turned an outage into a fabricated success.
    it "FAILS CLOSED when the live reconciler raises, instead of minting a false effective" do
      gate = gate_answering("auto_apply_within_bounds")
      stub_gate(gate)
      # VerificationService collapses EVERY per-instance result into one failing
      # `live_reconciliation` check when the reconciler raises — deliberately,
      # so silence cannot read as health. That name matches neither the
      # step_N_* nor the instance_* pattern.
      exploding = double("provision_verifier")
      allow(exploding).to receive(:reconcile_instances).and_raise(RuntimeError, "provider API down")
      allow(::Powernode::ExtensionRegistry).to receive(:provider)
        .with(:provision_verifier).and_return(exploding)

      plan = dispatch_and_complete!

      result = service.settle!(adaptation_plan_ids: [ plan.id ])

      expect(result[:healthy]).to be false
      expect(plan.reload.status).to eq("failed")
      # The whole point: no fabricated EFFECTIVE in the ground-truth table.
      expect(gate).not_to have_received(:record_adaptation_outcome!)
    end

    it "FAILS CLOSED when the reconciler answers for only some of the adaptation's instances" do
      gate = gate_answering("auto_apply_within_bounds")
      stub_gate(gate)
      partial = double("provision_verifier")
      allow(partial).to receive(:reconcile_instances) do |account:, expectations:|
        # Silently drops i-4 — the scored set shrinks without any check failing.
        expectations.reject { |e| e[:node_instance_id] == "i-4" }
             .map { |e| { node_instance_id: e[:node_instance_id], ok: true, detail: "running" } }
      end
      allow(::Powernode::ExtensionRegistry).to receive(:provider)
        .with(:provision_verifier).and_return(partial)

      plan = dispatch_and_complete!

      result = service.settle!(adaptation_plan_ids: [ plan.id ])

      expect(result[:healthy]).to be false
      expect(gate).not_to have_received(:record_adaptation_outcome!)
    end

    it "still treats core mode (no reconciler) as verifiable, not as a blocker" do
      gate = gate_answering("auto_apply_within_bounds")
      allow(gate).to receive(:record_adaptation_outcome!).and_return(nil)
      stub_gate(gate)
      # Core mode emits ONE passing `live_reconciliation` annotation and no
      # per-instance checks — unverifiable-but-said-so, which must not be
      # confused with the reconciler-error shape above.
      allow(::Powernode::ExtensionRegistry).to receive(:provider)
        .with(:provision_verifier).and_return(nil)

      plan = dispatch_and_complete!

      result = service.settle!(adaptation_plan_ids: [ plan.id ])

      expect(result[:healthy]).to be true
      expect(gate).to have_received(:record_adaptation_outcome!)
    end

    it "records NO outcome when the post-adapt verification is unhealthy" do
      gate = gate_answering("auto_apply_within_bounds")
      stub_gate(gate)

      plan = build_diff_plan!
      service.dispatch!(plan: plan)
      # Appended step FAILED — the adaptation did not land.
      live_plan.reload.steps.where(status: "pending").find_each do |s|
        s.update!(status: "failed", metadata: { "last_outputs" => {} })
      end

      result = service.settle!(adaptation_plan_ids: [ plan.id ])

      expect(result[:healthy]).to be false
      expect(gate).not_to have_received(:record_adaptation_outcome!)
      expect(plan.reload.status).to eq("failed")
    end

    it "records NO outcome for an operator-initiated adaptation (no sensor fingerprint to clear)" do
      gate = gate_answering("auto_apply_within_bounds")
      stub_gate(gate)

      plan = dispatch_and_complete!(fingerprint: nil)

      result = service.settle!(adaptation_plan_ids: [ plan.id ])

      expect(result[:healthy]).to be true
      # An operator request has no signal that could ever clear, so an outcome
      # keyed on a synthetic fingerprint would score EFFECTIVE for free on the
      # next tick — a manufactured success in the table the LEARN step reads.
      expect(gate).not_to have_received(:record_adaptation_outcome!)
      expect(plan.reload.status).to eq("completed")
    end
  end

  # ------------------------------------------------ runner completion hook ---

  describe "settle from the runner" do
    before do
      allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
      stub_confirming_verifier

      succeeding = Class.new do
        def self.descriptor = { rollback: nil }
        def execute(**_inputs)
          { success: true, data: { "outputs" => { "node_instance_ids" => %w[i-3 i-4] }, "failures" => [] } }
        end
      end
      allow(Ai::Provisioning::SkillCompositionRunner)
        .to receive(:resolve_executor).with("scale_project").and_return(succeeding)
    end

    # A runner over the live plan with the orchestrator stubbed, so an example
    # can assert whether the execute-phase advance was attempted.
    def build_runner
      runner = Ai::Provisioning::SkillCompositionRunner.new(
        account: account, mission: mission.reload, plan: live_plan.reload
      )
      orchestrator = instance_double(Ai::Missions::OrchestratorService)
      allow(orchestrator).to receive(:advance!)
      allow(orchestrator).to receive(:broadcast_step_event!)
      allow(runner).to receive(:orchestrator).and_return(orchestrator)
      runner
    end

    it "settles the adaptation when its steps complete" do
      gate = gate_answering("auto_apply_within_bounds")
      stub_gate(gate)
      plan = build_diff_plan!
      service.dispatch!(plan: plan)

      appended = live_plan.reload.steps.order(:step_number).last
      runner = build_runner

      runner.execute_step!(appended.reload)

      expect(plan.reload.status).to eq("completed")
      expect(gate).to have_received(:record_adaptation_outcome!)
    end

    it "settles the adaptation when its step FAILS, rather than leaving it executing" do
      gate = gate_answering("auto_apply_within_bounds")
      stub_gate(gate)
      plan = build_diff_plan!
      service.dispatch!(plan: plan)

      appended = live_plan.reload.steps.order(:step_number).last
      runner = build_runner
      failing = Class.new do
        def self.descriptor = { rollback: nil }
        def execute(**_inputs) = { success: false, error: "provider rejected the request" }
      end
      allow(Ai::Provisioning::SkillCompositionRunner)
        .to receive(:resolve_executor).with("scale_project").and_return(failing)

      runner.execute_step!(appended.reload)

      # The settle only ever ran off the success path, so a failed adaptation
      # sat in `executing` forever with no outcome and no failure record — and
      # the live plan then permanently held a non-completed step, which blocked
      # every LATER adaptation on this mission from settling too.
      expect(appended.reload.status).to eq("failed")
      expect(plan.reload.status).to eq("failed")
      expect(gate).not_to have_received(:record_adaptation_outcome!)
    end

    it "settles a CHAINED adaptation whose first step fails, instead of waiting on an unreachable second" do
      # persist_diff_plan! chains multi-step diffs, and dispatch_unblocked_successors
      # only runs on the SUCCESS arm — so a failed step 1 leaves step 2 `pending`
      # forever. Requiring every sibling to be terminal then never fires, and the
      # diff plan sits in `executing` with no outcome: the original permanent
      # stall, narrowed to multi-step adaptations.
      gate = gate_answering("auto_apply_within_bounds",
                            approval_request_id: SecureRandom.uuid, authority: "approval")
      stub_gate(gate)
      plan = build_diff_plan!(steps: [
        { "skill" => "scale_project", "on_failure" => "continue",
          "inputs" => { "change_type" => "scale_horizontal", "desired_replica_count" => 4,
                        "project_id" => mission.id, "target_count" => 2,
                        "scaling_strategy" => "add_replicas" } },
        { "skill" => "attach_storage", "on_failure" => "continue",
          "inputs" => { "mission_id" => mission.id } }
      ])
      service.dispatch!(plan: plan)

      first, second = live_plan.reload.steps.order(:step_number).to_a.last(2)
      runner = build_runner
      failing = Class.new do
        def self.descriptor = { rollback: nil }
        def execute(**_inputs) = { success: false, error: "provider rejected the request" }
      end
      allow(Ai::Provisioning::SkillCompositionRunner)
        .to receive(:resolve_executor).with("scale_project").and_return(failing)

      runner.execute_step!(first.reload)

      expect(first.reload.status).to eq("failed")
      # The unreachable successor is marked, not left dangling.
      expect(second.reload.status).to eq("failed")
      expect(plan.reload.status).to eq("failed")
      expect(gate).not_to have_received(:record_adaptation_outcome!)
    end

    it "still advances a mission adapted while it was in the EXECUTE phase" do
      # Nothing stops an operator adapting a mission mid-execute. Suppressing
      # the execute-phase advance whenever the plan carried adaptation
      # provenance stranded that mission in `execute` forever — the appended
      # steps keep their provenance, so the suppression never lifted and verify
      # was never reached.
      mission.update!(current_phase: "execute")
      stub_gate(gate_answering("auto_apply_within_bounds"))
      plan = build_diff_plan!
      service.dispatch!(plan: plan)

      appended = live_plan.reload.steps.order(:step_number).last
      runner = build_runner
      orchestrator = runner.orchestrator

      runner.execute_step!(appended.reload)

      expect(orchestrator).to have_received(:advance!).with(expected_phase: "execute")
      expect(plan.reload.status).to eq("completed")
    end
  end
end
