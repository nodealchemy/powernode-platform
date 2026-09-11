# frozen_string_literal: true

require "rails_helper"

# POST /api/v1/internal/ai/goal_plans/execute_step — goal_plans ruling, option A.
#
# The endpoint used to crash at `step.goal_plan` (the association is `plan`)
# before doing anything, so every agent_execution step sat in "executing"
# forever while AiGoalPlanExecutionJob retried into the 500. Behind that crash,
# every allowed step type fell through to "Completed step type: X": fixing only
# the crash would have marked agent steps completed with no agent ever run.
#
# Now no step type has a dispatcher here, so a step sent here FAILS with a named
# reason and nothing completes without doing its work. The worker gets 200 with
# status failed in the BODY, which it logs and does not retry.
RSpec.describe "Api::V1::Internal::Ai::GoalPlans", type: :request do
  let(:account) { create(:account) }
  let(:worker) { create(:worker, account: account) }
  let(:headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")) }
  end
  let(:agent) { create(:ai_agent, account: account) }
  let(:goal) do
    Ai::AgentGoal.create!(account: account, agent: agent, title: "Keep the lint queue empty",
                          goal_type: "improvement", status: "active", priority: 3, progress: 0)
  end
  let(:plan) { Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "executing", version: 1) }

  def step_of(type, number: 1, status: "executing", dependencies: [])
    Ai::GoalPlanStep.create!(plan: plan, step_number: number, status: status, step_type: type,
                             dependencies: dependencies)
  end

  def execute!(step)
    post "/api/v1/internal/ai/goal_plans/execute_step",
         params: { step_id: step.id }, headers: headers, as: :json
  end

  def data = JSON.parse(response.body)["data"]

  # The real shape: RalphLoopClosureService starts an agent_execution step,
  # then enqueues the job that calls this endpoint.
  it "fails an agent_execution step with a named reason, and answers 200 with status failed in the BODY" do
    step = step_of("agent_execution")

    execute!(step)

    expect(response).to have_http_status(:ok)
    expect(data).to include("step_id" => step.id, "status" => "failed",
                            "reason" => "no dispatcher for step type agent_execution",
                            "plan_progress" => 0.0)
    expect(step.reload).to have_attributes(status: "failed",
                                           result_summary: "no dispatcher for step type agent_execution")
    # Deterministic, so self-correct never pays to replan it (goal-plan ruling 2).
    expect(step.metadata).to include("failure_kind" => "no_dispatcher", "failure_class" => "deterministic")
  end

  it "completes no step type without doing its work, and leaves the plan where it was" do
    steps = Ai::GoalPlanStep::STEP_TYPES.each_with_index.map { |type, i| step_of(type, number: i + 1) }

    steps.each do |step|
      execute!(step)
      expect(data).to include("status" => "failed", "reason" => "no dispatcher for step type #{step.step_type}")
    end

    expect(Ai::GoalPlanStep.where(plan: plan).distinct.pluck(:status)).to eq([ "failed" ])
    expect(plan.reload.status).to eq("executing")
  end

  it "refuses a step whose dependencies are not met, and leaves it untouched" do
    step_of("observation", number: 1, status: "pending")
    blocked = step_of("agent_execution", number: 2, dependencies: [ 1 ])

    execute!(blocked)

    expect(response).to have_http_status(:unprocessable_content)
    expect(blocked.reload.status).to eq("executing")
  end

  it "answers 404 for a step that does not exist" do
    post "/api/v1/internal/ai/goal_plans/execute_step",
         params: { step_id: SecureRandom.uuid }, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
