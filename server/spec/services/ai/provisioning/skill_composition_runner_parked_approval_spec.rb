# frozen_string_literal: true

require "rails_helper"
require "ostruct"

# APO-1f (IMP-117b34656921) — the CONSUMER half.
#
# Once a gated skill executor answers the platform's pending envelope
# (success: true + data.pending), a consumer that keys on `success` alone reads
# a PARKED action as DONE. For this runner that is the worst possible reading:
# it would mark the step completed, hand its (empty) pending body to every
# downstream step as `depends_on_outputs`, and dispatch successors against
# infrastructure nothing created.
#
# The step must PARK instead, and the plan must resume when the approval
# releases — through the seam that already replays the executor,
# Ai::DeferredOperation#execute_now!.
RSpec.describe Ai::Provisioning::SkillCompositionRunner, "parked approvals" do
  let(:account)      { instance_double("Account", id: "acc-uuid-1") }
  let(:conversation) { instance_double("Ai::Conversation") }
  let(:mission)      { instance_double("Ai::Mission", id: "mission-uuid-1", conversation: conversation) }

  let(:pending_envelope) do
    {
      success: true,
      pending: true,
      data: {
        pending: true,
        action_category: "system.zz_gated",
        deferred_operation_id: "op-uuid-1",
        approval_request_id: "req-uuid-1",
        message: "Approval required: system.zz_gated"
      }
    }
  end

  let(:fake_executor_class) do
    Class.new do
      class << self
        attr_accessor :execute_result, :rollback_calls
      end

      def self.descriptor
        { name: "provision_full_stack", rollback: :rollback }
      end

      def initialize(account: nil)
        @account = account
      end

      def execute(**_inputs)
        self.class.execute_result
      end

      def rollback(**outputs)
        self.class.rollback_calls ||= []
        self.class.rollback_calls << outputs
        { success: true }
      end
    end
  end

  let(:step1) { build_step(id: "step-1", step_number: 1, dependencies: [],  on_failure: "rollback") }
  let(:step2) { build_step(id: "step-2", step_number: 2, dependencies: [ 1 ], on_failure: "continue") }
  let(:plan)  { OpenStruct.new(id: "plan-1", steps: PlanStepSet.new([ step1, step2 ])) }

  subject(:runner) { described_class.new(account: account, mission: mission, plan: plan) }

  before do
    fake_executor_class.execute_result = pending_envelope
    fake_executor_class.rollback_calls = []
    allow(MissionChannel).to receive(:broadcast_mission_event)
    allow(conversation).to receive(:add_system_message)
    allow(WorkerJobService).to receive(:enqueue_job)
    allow(runner).to receive(:resolve_executor).with("provision_full_stack").and_return(fake_executor_class)
  end

  describe "a step whose executor parks an approval" do
    it "does NOT mark the step completed" do
      runner.execute_step!(step1)

      expect(step1.status).not_to eq("completed")
    end

    it "parks the step in an awaiting_approval state" do
      runner.execute_step!(step1)

      expect(step1.status).to eq(described_class::PARKED_STATUS)
    end

    it "records the approval identifiers so an operator (and the resume) can find it" do
      runner.execute_step!(step1)

      parked = step1.metadata[described_class::PARKED_APPROVAL_KEY]
      expect(parked["deferred_operation_id"]).to eq("op-uuid-1")
      expect(parked["approval_request_id"]).to eq("req-uuid-1")
      expect(parked["action_category"]).to eq("system.zz_gated")
    end

    it "does not dispatch successors — nothing was applied" do
      runner.execute_step!(step1)

      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end

    it "does not roll the step back — a parked approval created nothing" do
      runner.execute_step!(step1)

      expect(fake_executor_class.rollback_calls).to be_empty
    end

    it "reports pending to its caller rather than a bare failure" do
      result = runner.execute_step!(step1)

      expect(result[:pending]).to be true
      expect(result[:success]).to be false
      expect(result[:approval_request_id]).to eq("req-uuid-1")
    end
  end

  describe "#resume_step!" do
    before { runner.execute_step!(step1) }

    it "completes the step from the replayed executor result and dispatches successors" do
      runner.resume_step!(step1, result: { success: true, data: { instance_id: "i-1" } })

      expect(step1.status).to eq("completed")
      expect(runner.send(:recorded_outputs_for, step1)[:instance_id]).to eq("i-1")
      expect(WorkerJobService).to have_received(:enqueue_job).once
    end

    it "fails the step when the released operation failed" do
      runner.resume_step!(step1, result: { success: false, error: "boom" })

      expect(step1.status).to eq("failed")
    end

    it "refuses to resume a step that is not parked" do
      step2.status = "pending"
      out = runner.resume_step!(step2, result: { success: true, data: {} })

      expect(out[:skipped]).to be true
      expect(step2.status).to eq("pending")
    end
  end

  # ===== Real-DB fixtures for the resume doors =====
  #
  # A released Ai::DeferredOperation names no plan, so the runner locates the
  # parked step by the operation id it stamped on the step's metadata. That read
  # is a real query, so these are real rows.
  let(:real_account) { create(:account) }
  let(:real_user)    { create(:user, account: real_account) }
  let(:real_provider) { create(:ai_provider, account: real_account, is_active: true) }
  let(:real_agent) do
    create(:ai_agent, account: real_account, provider: real_provider, creator: real_user, status: "active")
  end

  let(:goal) do
    Ai::AgentGoal.create!(
      account: real_account, agent: real_agent, title: "Provision",
      description: "d", goal_type: "improvement", status: "pending",
      priority: 3, progress: 0.0, success_criteria: {}, metadata: {}
    )
  end

  let(:real_plan) do
    Ai::GoalPlan.create!(account: real_account, goal: goal, agent: real_agent,
                         status: "draft", version: 1, plan_data: { "kind" => "provisioning" })
  end

  let(:real_mission) do
    Ai::Mission.create!(account: real_account, created_by: real_user, name: "m",
                        mission_type: "infrastructure", status: "active",
                        configuration: { "plan" => { "plan_id" => real_plan.id } })
  end

  let(:operation) do
    Ai::DeferredOperation.create!(
      account: real_account, action_category: "system.zz_gated",
      executor_class: "ZzGatedFixtureExecutor", params: { "widget_id" => "w-1" },
      requested_by: real_user
    )
  end

  let(:parked_step) do
    real_mission
    real_plan.steps.create!(
      step_number: 1, step_type: "provisioning_skill",
      status: described_class::PARKED_STATUS, description: "gated",
      execution_config: { "skill" => "provision_full_stack", "inputs" => {}, "on_failure" => "continue" },
      dependencies: [],
      metadata: { described_class::PARKED_APPROVAL_KEY => {
        "deferred_operation_id" => operation.id,
        "approval_request_id" => nil,
        "action_category" => "system.zz_gated"
      } }
    )
  end

  # The class-level entry point the replay seam calls.
  describe ".resume_parked_step" do
    before { parked_step }

    it "finds the parked step by deferred operation and completes it" do
      described_class.resume_parked_step(
        deferred_operation: operation,
        result: { success: true, data: { widget_id: "w-1" } }
      )

      expect(parked_step.reload.status).to eq("completed")
    end

    it "returns nil when no parked step belongs to the operation" do
      parked_step.update!(status: "completed")

      expect(
        described_class.resume_parked_step(deferred_operation: operation, result: { success: true, data: {} })
      ).to be_nil
    end

    # REVIEW FINDING (major): the replay hands over the executor's RAW return —
    # the value Ai::DeferredOperation#execute_now! deliberately keeps OUT of its
    # own row ("a durable second copy outside Vault"). The runner then writes it
    # to ai_goal_plan_steps.metadata["last_outputs"] and result_summary, and
    # broadcasts it. A gated executor that MINTS material (federation
    # acceptance) would put that material in three durable/broadcast sinks.
    it "does not persist secret-named replay outputs verbatim" do
      described_class.resume_parked_step(
        deferred_operation: operation,
        result: { success: true, data: { acceptance_token: "s3cr3t-material", peer_id: "p-1" } }
      )

      outputs = parked_step.reload.metadata["last_outputs"]
      expect(outputs["acceptance_token"]).to eq(Ai::SensitiveParams::MASK)
      expect(outputs["peer_id"]).to eq("p-1")
    end
  end

  # REVIEW FINDING (major): #released_result_for re-wrapped the persisted row.
  # Ai::DeferredOperation#execute_now! persists the executor's WHOLE envelope
  # and completes the operation regardless of that envelope's own `success`, so
  # a re-wrap reads a FAILED skill as a completed step and double-wraps a
  # successful one out of reach of `depends_on_outputs`.
  describe "resuming from the durable row" do
    before { parked_step }

    it "fails the step when the completed operation persisted a FAILED envelope" do
      operation.update!(status: "completed", result: { "success" => false, "error" => "provider refused" })

      described_class.resume_parked_step(deferred_operation: operation)

      expect(parked_step.reload.status).to eq("failed")
    end

    it "carries the persisted envelope's own error onto the failed step" do
      operation.update!(status: "completed", result: { "success" => false, "error" => "provider refused" })

      described_class.resume_parked_step(deferred_operation: operation)

      expect(parked_step.reload.result_summary.to_s).to include("provider refused")
    end

    it "records the executor's data, not the envelope around it" do
      operation.update!(status: "completed",
                        result: { "success" => true, "data" => { "instance_id" => "i-7" } })

      described_class.resume_parked_step(deferred_operation: operation)

      expect(parked_step.reload.metadata["last_outputs"]).to eq("instance_id" => "i-7")
    end
  end

  # REVIEW FINDING (blocker): a REJECTED or EXPIRED approval never replays an
  # executor, so nothing reached the runner and the step sat in
  # awaiting_approval forever — its mission never advancing and every later
  # adaptation on that mission blocked behind it. Before APO-1f the step was
  # recorded FAILED, so this was a regression.
  describe "an approval decision that is not an approval" do
    before { parked_step }

    it "fails the parked step when the approval is REJECTED" do
      request = instance_double("Ai::ApprovalRequest", status: "rejected")

      operation.on_approval_decision(request)

      expect(parked_step.reload.status).to eq("failed")
    end

    it "fails the parked step when the approval EXPIRES" do
      request = instance_double("Ai::ApprovalRequest", status: "expired")

      operation.on_approval_decision(request)

      expect(parked_step.reload.status).to eq("failed")
    end

    it "still reports the decision as dispatched to the approval request" do
      request = instance_double("Ai::ApprovalRequest", status: "rejected")

      expect(operation.on_approval_decision(request)).to eq(Ai::ApprovalRequest::DISPATCH_EXECUTED)
    end
  end

  def build_step(id:, step_number:, dependencies:, on_failure:)
    cfg = { "skill" => "provision_full_stack", "inputs" => {}, "on_failure" => on_failure }
    OpenStruct.new(
      id: id, step_number: step_number, dependencies: dependencies,
      execution_config: cfg, status: "pending", metadata: {}, result_summary: nil
    ).tap do |s|
      def s.update!(attrs)
        attrs.each { |k, v| public_send("#{k}=", v) }
      end
    end
  end

  class PlanStepSet
    include Enumerable
    def initialize(steps) = @steps = steps
    def each(&block) = @steps.each(&block)
    def in_order = @steps.sort_by { |s| s.step_number.to_i }
    def to_a = @steps.to_a
  end
end
