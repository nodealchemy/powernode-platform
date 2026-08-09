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
      expect(conversation).to have_received(:add_system_message).with(
        a_string_including("Provisioning run started"),
        hash_including(activity_type: "provisioning_step_progress",
                       metadata: hash_including(:runner_id, status: "started"))
      )
    end

    it "computes layers correctly from dependencies (1 → 2,3 → 4)" do
      layers = runner.send(:topological_layers, [step1, step2, step3, step4])
      expect(layers.map { |layer| layer.map(&:step_number) }).to eq([[1], [2, 3], [4]])
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

      it "emits a step_changed broadcast and a system message" do
        runner.execute_step!(step1)

        expect(MissionChannel).to have_received(:broadcast_mission_event).with(
          mission.id,
          "provisioning_step_changed",
          hash_including(step_id: step1.id, status: "completed", outputs: { node_id: "n-1" })
        )
        expect(conversation).to have_received(:add_system_message).with(
          a_string_including("Step 1 (provision_full_stack) → completed"),
          hash_including(activity_type: "provisioning_step_progress",
                         metadata: hash_including(status: "completed"))
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
end
