# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe Ai::Provisioning::SkillCompositionRunner do
  # We use a real fake executor class plus lightweight in-memory step / plan
  # doubles. The runner consumes a duck-typed contract — it doesn't need real
  # Ai::GoalPlan / Ai::GoalPlanStep records — and a fake class is honest with
  # rspec-mocks' verify_partial_doubles (anonymous Class.new doesn't define
  # the methods we'd stub).

  let(:account)      { instance_double("Account", id: "acc-uuid-1") }
  let(:conversation) { instance_double("Ai::Conversation") }
  let(:mission)      { instance_double("Ai::Mission", id: "mission-uuid-1", conversation: conversation) }

  # ---- Real fake executor class -------------------------------------------
  # Class-level mutable state lets each example dial in success / failure /
  # raise behavior, and lets us verify that execute / rollback were called
  # with the expected inputs.
  let(:fake_executor_class) do
    Class.new do
      class << self
        attr_accessor :execute_result, :execute_calls, :rollback_calls, :rollback_result
      end

      def self.descriptor
        { name: "provision_full_stack", rollback: :rollback }
      end

      def initialize(account: nil)
        @account = account
      end

      def execute(**inputs)
        self.class.execute_calls ||= []
        self.class.execute_calls << inputs

        result = self.class.execute_result
        raise result if result.is_a?(Exception)
        result || { success: true, data: {} }
      end

      def rollback(**outputs)
        self.class.rollback_calls ||= []
        self.class.rollback_calls << outputs
        self.class.rollback_result || { success: true }
      end
    end
  end

  let(:step1) { build_step(id: "step-1", step_number: 1, dependencies: [],  skill: "provision_full_stack", on_failure: "continue") }
  let(:step2) { build_step(id: "step-2", step_number: 2, dependencies: [1], skill: "provision_full_stack", on_failure: "continue") }
  let(:step3) { build_step(id: "step-3", step_number: 3, dependencies: [1], skill: "provision_full_stack", on_failure: "rollback") }
  let(:step4) { build_step(id: "step-4", step_number: 4, dependencies: [2, 3], skill: "provision_full_stack", on_failure: "continue") }

  let(:plan) { build_plan([step1, step2, step3, step4]) }

  subject(:runner) { described_class.new(account: account, mission: mission, plan: plan) }

  before do
    fake_executor_class.execute_result = nil
    fake_executor_class.execute_calls = []
    fake_executor_class.rollback_calls = []
    fake_executor_class.rollback_result = nil

    allow(MissionChannel).to receive(:broadcast_mission_event)
    allow(conversation).to receive(:add_system_message)
    allow(WorkerJobService).to receive(:enqueue_job)
    allow(runner).to receive(:resolve_executor).with("provision_full_stack").and_return(fake_executor_class)
  end

  describe "#execute!" do
    it "returns runner_id (UUID7), started_at and step_count" do
      result = runner.execute!

      expect(result[:runner_id]).to be_a(String)
      expect(result[:runner_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      expect(result[:started_at]).to be_a(Time)
      expect(result[:step_count]).to eq(4)
    end

    it "dispatches only the first parallel-safe layer (no-deps steps)" do
      runner.execute!

      expect(WorkerJobService).to have_received(:enqueue_job).with(
        "AiProvisioningStepJob",
        hash_including(
          args: hash_including(
            mission_id: mission.id,
            step_id: step1.id,
            account_id: account.id
          )
        )
      ).once

      expect(WorkerJobService).not_to have_received(:enqueue_job).with(
        "AiProvisioningStepJob",
        hash_including(args: hash_including(step_id: step2.id))
      )
    end

    it "broadcasts a run_started event and posts a system message" do
      runner.execute!

      expect(MissionChannel).to have_received(:broadcast_mission_event).with(
        mission.id,
        "provisioning_run_started",
        hash_including(:runner_id, :started_at, step_count: 4, layer_count: 3)
      )
      # Asserted the top-level activity_type:/metadata: shape until IMP-019fe4c5 —
      # the instance_double accepted it, so this stayed green while every one of
      # these messages was actually being dropped by Ai::Message.
      expect(conversation).to have_received(:add_system_message).with(
        a_string_including("Provisioning run started"),
        content_metadata: hash_including("activity_type" => "provisioning_step_progress",
                                         "runner_id" => anything,
                                         "status" => "started")
      )
    end

    it "computes layers correctly from dependencies (1 → 2,3 → 4)" do
      layers = runner.send(:topological_layers, [step1, step2, step3, step4])
      expect(layers.map { |layer| layer.map(&:step_number) }).to eq([[1], [2, 3], [4]])
    end
  end

  # IMP-6025e4c2e256 — layering a SUBSET of the plan.
  #
  # AdaptationDispatchService hands #execute_appended! only the steps that
  # still need enqueueing. On a resume that is a strict subset of the
  # adaptation, and by construction every step in it depends on rows OUTSIDE
  # the collection handed over — the COMPLETED steps that made it resumable in
  # the first place. A layerer that can satisfy a dependency only from within
  # the collection it was given therefore cannot layer a subset at all: the
  # first pass yields an empty layer and the genuine-cycle backstop fires on a
  # perfectly ordered chain.
  describe "#execute_appended! — layering a subset against the live plan" do
    # The live plan's original step, long since finished.
    let(:original) do
      build_step(id: "orig-1", step_number: 1, dependencies: [], skill: "provision_full_stack",
                 on_failure: "continue").tap { |s| s.status = "completed" }
    end
    # Appended, with no dependencies of its own.
    let(:free) do
      build_step(id: "app-2", step_number: 2, dependencies: [], skill: "provision_full_stack",
                 on_failure: "continue")
    end
    # Appended, depending on the COMPLETED original — outside any resumable subset.
    let(:chained) do
      build_step(id: "app-3", step_number: 3, dependencies: [1], skill: "provision_full_stack",
                 on_failure: "continue")
    end
    # Appended, depending on `chained`, which is still PENDING inside the subset.
    let(:blocked) do
      build_step(id: "app-4", step_number: 4, dependencies: [3], skill: "provision_full_stack",
                 on_failure: "continue")
    end

    let(:plan)     { build_plan([original, free, chained, blocked]) }
    let(:enqueued) { [] }

    before do
      allow(WorkerJobService).to receive(:enqueue_job) { |*args| enqueued << args[1][:args][:step_id]; true }
    end

    it "enqueues a resumed step whose only dependency COMPLETED outside the subset" do
      result = runner.execute_appended!(steps: [free, chained])

      # `chained` is ready — step 1 completed — and nothing else picks it up.
      # dispatch_unblocked_successors only fires when a step COMPLETES, so if
      # `free` fails instead, `chained` sits pending forever:
      # fail_unreachable_adaptation_successors! ignores it (its predecessor
      # completed, it did not fail), the adaptation's steps never all reach a
      # terminal status, and the diff plan never leaves `executing`.
      expect(enqueued).to contain_exactly(free.id, chained.id)
      expect(result[:dispatched]).to eq(2)
    end

    it "still HOLDS BACK a step whose dependency is inside the subset and still pending" do
      # The negative control for the seed. Satisfying dependencies from an
      # explicitly-completed set must not degrade into `deps & subset`, nor
      # into "ignore a dependency I cannot see": an unready subset stays
      # unready, and `blocked` waits for `chained` to finish.
      result = runner.execute_appended!(steps: [chained, blocked])

      expect(enqueued).to eq([chained.id])
      expect(result[:dispatched]).to eq(1)
    end

    it "does not warn about a dependency cycle for a legitimately chained resume" do
      # The shape every resume takes today: AdaptationProposerService chains
      # each diff linearly, so a resumable set is one step whose predecessor
      # completed. Warning "dependency cycle or unresolved deps" here poisons a
      # real diagnostic — the log line means nothing once it fires on the
      # healthy path.
      allow(Rails.logger).to receive(:warn).and_call_original

      runner.execute_appended!(steps: [chained])

      expect(Rails.logger).not_to have_received(:warn).with(/dependency cycle or unresolved deps/)
      expect(enqueued).to eq([chained.id])
    end

    it "STILL takes the best-effort branch for a genuine cycle" do
      # Positive control for the backstop the seed must not remove. A real
      # cycle has no satisfiable seed, so it must keep warning AND keep
      # emitting its steps, so they surface as failures instead of vanishing.
      a = build_step(id: "cyc-5", step_number: 5, dependencies: [6], skill: "provision_full_stack",
                     on_failure: "continue")
      b = build_step(id: "cyc-6", step_number: 6, dependencies: [5], skill: "provision_full_stack",
                     on_failure: "continue")
      cyclic = described_class.new(account: account, mission: mission,
                                   plan: build_plan([original, a, b]))
      allow(Rails.logger).to receive(:warn).and_call_original

      result = cyclic.execute_appended!(steps: [a, b])

      expect(Rails.logger).to have_received(:warn).with(/dependency cycle or unresolved deps/)
      expect(enqueued).to contain_exactly(a.id, b.id)
      expect(result[:dispatched]).to eq(2)
    end
  end

  describe "#fail_unreachable_adaptation_successors!" do
    it "announces each unreachable successor ONCE, even when the step cannot record its own failure" do
      # The siblings.size bound replaced a hang with repeated work. mark_failed
      # deliberately no-ops for a step responding to neither fail! nor update!
      # — a duck-typed shape this runner explicitly accepts — so `newly`
      # re-selected the same still-"pending" step on every pass and announced
      # it again each time, duplicating the broadcast and the system message a
      # console subscribed to MissionChannel renders.
      dead = build_step(id: "d-1", step_number: 1, dependencies: [], skill: "provision_full_stack",
                        on_failure: "continue").tap { |s| s.status = "failed" }
      # No update!/fail! — mark_failed cannot move it, which is the whole point.
      undead = OpenStruct.new(id: "d-2", step_number: 2, dependencies: [1], status: "pending",
                              execution_config: { "skill" => "provision_full_stack" }, metadata: {})

      announced = []
      allow(runner).to receive(:announce_step) { |s, **_kw| announced << s.step_number }

      runner.send(:fail_unreachable_adaptation_successors!, [dead, undead])

      expect(announced).to eq([2])
    end
  end

  describe "#execute_step!" do
    before { runner.execute! } # establishes runner_id

    context "on success" do
      before { fake_executor_class.execute_result = { success: true, data: { node_id: "n-1" } } }

      it "invokes the resolved executor with the step's inputs" do
        runner.execute_step!(step1)
        expect(fake_executor_class.execute_calls.last).to eq(template_id: "tmpl-1", count: 1)
      end

      it "marks the step completed and returns success+outputs" do
        result = runner.execute_step!(step1)

        expect(result[:success]).to be true
        expect(result[:outputs]).to eq(node_id: "n-1")
        expect(step1.status).to eq("completed")
      end

      it "dispatches the now-unblocked successors (step2 + step3)" do
        runner.execute_step!(step1)

        expect(WorkerJobService).to have_received(:enqueue_job).with(
          "AiProvisioningStepJob",
          hash_including(args: hash_including(step_id: step2.id))
        )
        expect(WorkerJobService).to have_received(:enqueue_job).with(
          "AiProvisioningStepJob",
          hash_including(args: hash_including(step_id: step3.id))
        )
      end

      # F6 (IMP 019fe4c5-03a4): execute previously completed its last step and
      # SAT there until an operator called /advance by hand. The runner is the
      # only component that knows when the DAG is done — it advances the
      # mission out of execute itself.
      it "advances the mission out of execute when the LAST step completes" do
        [ step1, step2, step3 ].each { |s| s.status = "completed" }
        orchestrator = instance_double(Ai::Missions::OrchestratorService)
        allow(runner).to receive(:orchestrator).and_return(orchestrator)
        allow(orchestrator).to receive(:broadcast_step_event!)
        expect(orchestrator).to receive(:advance!).with(hash_including(expected_phase: "execute"))

        runner.execute_step!(step4)
      end

      it "does NOT advance while steps remain" do
        step1.status = "completed"
        orchestrator = instance_double(Ai::Missions::OrchestratorService)
        allow(runner).to receive(:orchestrator).and_return(orchestrator)
        allow(orchestrator).to receive(:broadcast_step_event!)
        expect(orchestrator).not_to receive(:advance!)

        runner.execute_step!(step2)
      end

      it "emits a step_changed broadcast and a system message" do
        runner.execute_step!(step1)

        expect(MissionChannel).to have_received(:broadcast_mission_event).with(
          mission.id,
          "provisioning_step_changed",
          hash_including(step_id: step1.id, status: "completed", outputs: { node_id: "n-1" })
        )
        expect(conversation).to have_received(:add_system_message).with(
          a_string_including("Step 1 (provision_full_stack) → completed"),
          content_metadata: hash_including("activity_type" => "provisioning_step_progress",
                                           "status" => "completed")
        )
      end
    end

    context "when the executor returns failure with on_failure: continue" do
      before do
        fake_executor_class.execute_result = { success: false, error: "no capacity" }
        step1.status = "completed" # so step2 is logically dispatchable
      end

      it "marks the step failed and returns the error" do
        result = runner.execute_step!(step2)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("no capacity")
        expect(step2.status).to eq("failed")
      end

      it "does NOT roll back predecessors" do
        runner.execute_step!(step2)
        expect(fake_executor_class.rollback_calls).to be_empty
      end
    end

    context "when the executor raises with on_failure: rollback" do
      before do
        # step1 + step2 already complete WITH recorded resources; step3 fails.
        # F-b (IMP 019fe5d7-1089, dryrun 20260809b): rollback previously walked
        # completed predecessors and terminated a SIBLING step's healthy
        # instance 20s after its successful provision — a step that failed on
        # input validation, having created nothing, destroyed good
        # infrastructure. Rollback scope is now the FAILED STEP'S OWN recorded
        # resources, nothing else; disposition of healthy siblings belongs to
        # verify (F2) and the operator gates.
        step1.status = "completed"
        step1.metadata = { "last_outputs" => { "outputs" => { "node_instance_ids" => %w[a-1 a-2] } } }
        step2.status = "completed"
        step2.metadata = { "last_outputs" => { "outputs" => { "node_instance_ids" => %w[b-1] } } }
        fake_executor_class.execute_result = StandardError.new("provider 500")
      end

      it "compensates ONLY the failed step — completed siblings' resources survive" do
        result = runner.execute_step!(step3)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("provider 500")
        rolled_ids = fake_executor_class.rollback_calls.flat_map { |c| Array(c[:node_instance_ids]) }
        expect(rolled_ids).not_to include("a-1", "a-2", "b-1")
      end

      it "invokes the failed step's own rollback hook with its own recorded outputs" do
        # A retried step may carry outputs from a prior partial success — those
        # ARE this step's resources and are the legitimate compensation target.
        step3.metadata = { "last_outputs" => { "outputs" => { "node_instance_ids" => %w[c-9] } } }
        runner.execute_step!(step3)

        expect(fake_executor_class.rollback_calls.size).to eq(1)
        expect(fake_executor_class.rollback_calls.last).to include(node_instance_ids: %w[c-9])
      end

      it "rolls back NOTHING when the failed step recorded no outputs" do
        # The 20260809b shape: input validation failed before anything was
        # created — there is nothing of this step's to compensate.
        runner.execute_step!(step3)
        expect(fake_executor_class.rollback_calls.flat_map { |c| Array(c[:node_instance_ids]) }).to be_empty
      end
    end
  end

  describe "#rollback_step!" do
    before do
      runner.execute! # init runner_id
      step1.status = "completed"
      step1.metadata = { "last_outputs" => { "node_id" => "n-1" } }
    end

    it "invokes descriptor[:rollback] on the executor with the recorded outputs" do
      runner.rollback_step!(step1)
      expect(fake_executor_class.rollback_calls).to eq([{ node_id: "n-1" }])
    end

    it "flattens a nested 'outputs' sub-hash so rollback hooks receive ids as flat kwargs" do
      # Mirrors the nested-outputs convention (provision_full_stack et al.):
      # ids live under data.outputs.*, but rollback hooks declare them flat.
      # Without flattening, shallow symbolize would never surface node_id and
      # the rollback would silently no-op.
      step1.metadata = { "last_outputs" => { "count" => 1, "outputs" => { "node_id" => "n-9" } } }
      runner.rollback_step!(step1)
      expect(fake_executor_class.rollback_calls.last).to include(node_id: "n-9")
    end

    it "marks the step rolled_back and returns success" do
      result = runner.rollback_step!(step1)
      expect(result[:success]).to be true
      expect(step1.status).to eq("failed")
      expect(step1.result_summary[:rolled_back]).to be true
    end

    it "surfaces a hook that reports failure instead of swallowing it" do
      # 20260809b: the provision rollback hook returned
      # { success: false, errors: [...] } for one instance and the runner
      # discarded it — the surviving VM's non-termination was invisible.
      fake_executor_class.rollback_result = { success: false,
                                              errors: [{ resource: "node_instance", id: "n-1", error: "VM is locked" }] }
      result = runner.rollback_step!(step1)
      expect(result[:success]).to be false
      expect(MissionChannel).to have_received(:broadcast_mission_event).with(
        mission.id, "provisioning_step_changed", hash_including(status: "rollback_failed")
      )
    end

    it "emits a rolled_back broadcast" do
      runner.rollback_step!(step1)
      expect(MissionChannel).to have_received(:broadcast_mission_event).with(
        mission.id,
        "provisioning_step_changed",
        hash_including(step_id: step1.id, status: "rolled_back")
      )
    end

    it "returns success: false if the rollback hook itself raises" do
      # Override the rollback method on the fake class for this single example.
      fake_executor_class.class_eval do
        define_method(:rollback) { |**_| raise StandardError, "teardown failed" }
      end

      result = runner.rollback_step!(step1)
      expect(result[:success]).to be false
    end
  end

  describe "#execute_step! — cross-step data flow (depends_on_outputs)" do
    # These plans complete their whole DAG in one step-execution, which would
    # now trigger the F6 end-of-DAG advance — not this describe's concern.
    before { allow(runner).to receive(:advance_mission_if_dag_complete!) }

    # A provider step produces nested array outputs; a consumer step declares
    # depends_on_outputs to pull a scalar from the provider's recorded outputs.
    # Mirrors the real provision_full_stack → deploy_app_code contract, where
    # the provider emits data.outputs.node_instance_ids (plural array, nested)
    # and the consumer needs node_instance_id (singular scalar, required).
    let(:provider_step) do
      build_step(id: "prov", step_number: 1, dependencies: [], skill: "provision_full_stack", on_failure: "continue")
    end
    let(:consumer_step) do
      build_step(
        id: "cons", step_number: 2, dependencies: [1], skill: "provision_full_stack", on_failure: "continue",
        depends_on_outputs: {
          "node_instance_id" => { "from_step" => 1, "path" => "outputs.node_instance_ids", "select" => "first" }
        }
      )
    end
    let(:plan) { build_plan([provider_step, consumer_step]) }

    before { runner.execute! }

    it "threads a predecessor's nested array output into the consumer's scalar input" do
      fake_executor_class.execute_result = { success: true, data: { "outputs" => { "node_instance_ids" => %w[ni-1 ni-2] } } }
      runner.execute_step!(provider_step)

      fake_executor_class.execute_result = { success: true, data: {} }
      runner.execute_step!(consumer_step)

      expect(fake_executor_class.execute_calls.last).to include(node_instance_id: "ni-1")
    end

    it "honors the 'all' selector (passes the whole array through unchanged)" do
      consumer_step.execution_config["depends_on_outputs"]["node_instance_id"]["select"] = "all"
      fake_executor_class.execute_result = { success: true, data: { "outputs" => { "node_instance_ids" => %w[ni-1 ni-2] } } }
      runner.execute_step!(provider_step)

      fake_executor_class.execute_result = { success: true, data: {} }
      runner.execute_step!(consumer_step)

      expect(fake_executor_class.execute_calls.last[:node_instance_id]).to eq(%w[ni-1 ni-2])
    end

    it "leaves the input unset when the upstream output is missing (no nil clobber)" do
      fake_executor_class.execute_result = { success: true, data: { "outputs" => {} } }
      runner.execute_step!(provider_step)

      fake_executor_class.execute_calls.clear
      fake_executor_class.execute_result = { success: true, data: {} }
      runner.execute_step!(consumer_step)

      expect(fake_executor_class.execute_calls.last).not_to have_key(:node_instance_id)
    end
  end

  # =========================================================================
  # Helpers — minimal in-memory step / plan doubles that mimic the
  # Ai::GoalPlan / Ai::GoalPlanStep duck type the runner consumes.
  # =========================================================================

  def build_step(id:, step_number:, dependencies:, skill:, on_failure:, depends_on_outputs: nil)
    inputs = { template_id: "tmpl-1", count: 1 }
    cfg = { "skill" => skill, "inputs" => inputs, "on_failure" => on_failure }
    cfg["depends_on_outputs"] = depends_on_outputs if depends_on_outputs
    OpenStruct.new(
      id: id,
      step_number: step_number,
      dependencies: dependencies,
      execution_config: cfg,
      status: "pending",
      metadata: {},
      result_summary: nil
    ).tap do |s|
      def s.update!(attrs)
        attrs.each { |k, v| public_send("#{k}=", v) }
      end
    end
  end

  def build_plan(steps)
    OpenStruct.new(id: "plan-1", steps: PlanSteps.new(steps))
  end

  class PlanSteps
    include Enumerable
    def initialize(steps)
      @steps = steps
    end
    def each(&block) = @steps.each(&block)
    def in_order
      @steps.sort_by { |s| s.step_number.to_i }
    end
    def to_a = @steps.to_a
  end

  # IMP-019fe4c5-3d8e: post_system_message passed activity_type:/metadata: as
  # top-level kwargs. Ai::Conversation#add_message forwards **options straight into
  # messages.build, and neither is a column on ai_messages — so every step-progress
  # message raised ActiveModel::UnknownAttributeError into this method's own rescue
  # and vanished. This needs a REAL conversation: an instance_double verifies only
  # add_system_message's (content, **options) signature, which the bad call satisfied.
  describe "#post_system_message" do
    let(:real_account)      { create(:account) }
    let(:real_conversation) { create(:ai_conversation, account: real_account) }
    let(:real_mission)      { instance_double("Ai::Mission", id: "mission-real-1", conversation: real_conversation) }
    let(:real_runner) do
      described_class.new(account: real_account, mission: real_mission, plan: [])
    end

    it "persists the progress message instead of losing it to the rescue" do
      expect {
        real_runner.send(:post_system_message, "step 1 running", status: "running", metadata: { "step_id" => "s1" })
      }.to change { real_conversation.messages.count }.by(1)
    end

    it "records the activity type and status where the other activity writers put them" do
      real_runner.send(:post_system_message, "step 1 running", status: "running", metadata: { "step_id" => "s1" })

      meta = real_conversation.messages.last.content_metadata
      expect(meta["activity_type"]).to eq(described_class::ACTIVITY_TYPE)
      expect(meta["status"]).to eq("running")
      expect(meta["step_id"]).to eq("s1")
    end

    # Both real call sites pass symbol keys, and one already carries :status —
    # merging string keys onto that unnormalized would write "status" twice.
    it "normalizes the symbol-keyed metadata its own callers pass" do
      real_runner.send(
        :post_system_message,
        "Step 2 (docker_provision) → completed",
        status: "completed",
        metadata: { step_id: "s2", status: "completed", outputs: { "node_instance_id" => "n1" } }
      )

      meta = real_conversation.messages.last.content_metadata
      expect(meta["step_id"]).to eq("s2")
      expect(meta["status"]).to eq("completed")
      expect(meta["outputs"]).to eq({ "node_instance_id" => "n1" })
      expect(meta.keys).to match_array(meta.keys.uniq)
    end
  end
end
