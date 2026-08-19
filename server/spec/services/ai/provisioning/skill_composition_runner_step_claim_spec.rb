# frozen_string_literal: true

require "rails_helper"

# IMP-ce77677917c7 (1) — execute_step!'s in-flight guard was an unlocked
# read-then-write: `step_status(step)` then, several lines later,
# `mark_executing(step)`. Two workers holding the same row can both read
# "pending" and both invoke the provisioning executor.
#
# MEASURED, not assumed, because the offer left it open:
#   * The worker is NOT single-threaded — worker/config/sidekiq.yml sets
#     :concurrency: 25 (the `[ai_execution, 2]` entry is a queue WEIGHT, not a
#     thread count).
#   * Fan-in is real and unguarded. On completion the runner dispatches any
#     newly-unblocked successor (runner:479), and dispatch_step_job (:400)
#     enqueues UNCONDITIONALLY with no already-dispatched check. A step
#     depending on two predecessors that finish concurrently is enqueued twice.
# So this is an active double-provision risk, not latent hardening.
#
# Reproduced deterministically WITHOUT threads — the test DB is shared and
# concurrent runs deadlock. Two AR instances of one row are loaded while it is
# still "pending"; each therefore holds a stale in-memory status, which is
# exactly the state two workers are in. The in-memory guard passes for both,
# so only a conditional UPDATE at the database can tell them apart.
RSpec.describe Ai::Provisioning::SkillCompositionRunner, "step claim" do
  let(:account) { create(:account) }
  let(:agent)   { create(:ai_agent, account: account) }
  let(:goal) do
    Ai::AgentGoal.create!(account: account, agent: agent, title: "provision",
                          goal_type: "creation", status: "active", priority: 3)
  end

  let(:plan) do
    Ai::GoalPlan.create!(account: account, ai_agent_id: agent.id, goal_id: goal.id,
                         status: "approved", version: 1)
  end

  let!(:step) do
    Ai::GoalPlanStep.create!(
      plan_id: plan.id, step_number: 1, status: "pending",
      step_type: "provisioning_skill", description: "provision",
      execution_config: { "skill" => "provision_full_stack", "inputs" => {} }
    )
  end

  let(:mission) { instance_double("Ai::Mission", id: SecureRandom.uuid, conversation: nil) }

  subject(:runner) do
    described_class.new(account: account, mission: mission, plan: [ step ])
  end

  before do
    # The executor itself is irrelevant here; what matters is HOW MANY TIMES it
    # is reached. Stubbed on the runner so the claim path runs for real.
    allow(runner).to receive(:resolve_executor).and_return(Class.new)
    allow(runner).to receive(:invoke_executor).and_return({ success: true, data: {} })
    allow(runner).to receive(:announce_step)
  end

  it "lets exactly one of two workers holding the same pending row proceed" do
    worker_a = Ai::GoalPlanStep.find(step.id)
    worker_b = Ai::GoalPlanStep.find(step.id)
    expect(worker_a.status).to eq("pending")
    expect(worker_b.status).to eq("pending")

    runner.send(:execute_step!, worker_a)
    result_b = runner.send(:execute_step!, worker_b)

    expect(result_b[:already_running]).to be(true),
                                          "both workers claimed a pending step — on a provisioning skill that is a double provision"
    expect(runner).to have_received(:invoke_executor).once
  end

  # CONTROL: a single worker on a pending step must still run. A claim that
  # refuses everything would satisfy the example above and break execution.
  it "still executes a step nothing else has claimed" do
    result = runner.send(:execute_step!, Ai::GoalPlanStep.find(step.id))

    expect(result[:already_running]).to be_falsey
    expect(runner).to have_received(:invoke_executor).once
    expect(step.reload.status).to eq("completed")
  end

  # CONTROL, and the trap the operator direction names explicitly: the runner
  # deliberately accepts non-AR doubles (mark_* branch on respond_to?,
  # stamp_dispatched! guards step.class.respond_to?(:where)). A naive
  # step.class.where(...).update_all makes EVERY double-based spec silently take
  # the already_running arm — a no-op that reports green. This pins that a
  # double still executes.
  it "still executes a non-ActiveRecord step double" do
    # A PLAIN object, not an instance_double: the point is a step that is not
    # an ActiveRecord record, so `step.class.respond_to?(:where)` is false and
    # the claim must fall back to the duck-typed path.
    double_step = Struct.new(:id, :status, :execution_config) do
      def update!(**) = nil
    end.new(SecureRandom.uuid, "pending",
            { "skill" => "provision_full_stack", "inputs" => {} })

    result = runner.send(:execute_step!, double_step)

    expect(result[:already_running]).to be_falsey,
                                        "a duck-typed step took the already_running arm — every double-based spec would silently no-op"
    expect(runner).to have_received(:invoke_executor).once
  end
end
