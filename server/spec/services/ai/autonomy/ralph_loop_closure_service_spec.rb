# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Autonomy::RalphLoopClosureService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  subject(:service) { described_class.new(account: account, agent: agent) }

  before do
    # Observe/orient: no observations so the cycle reaches the decide/act loop cleanly.
    pipeline = instance_double(Ai::Autonomy::ObservationPipelineService, run: [])
    allow(Ai::Autonomy::ObservationPipelineService).to receive(:new).and_return(pipeline)
  end

  describe "#execute_cycle decide/act loop" do
    # Regression: the per-cycle loop pushed to results[:decide] then `break if size >= 5`
    # BEFORE the case dispatch and `results[:act] << action`, so the 5th decided action
    # was recorded but never dispatched/acted (decide.size 5, act.size 4) — one actionable
    # item silently dropped every cycle.
    it "acts on every decided action up to the per-cycle cap of 5" do
      # 6 no-op actions (nil ids hit the `if found` guards, so no heavy work runs);
      # the cap should stop at 5, and all 5 decided must also be acted.
      actions = Array.new(6) { |i| { type: :evaluate_plan, plan_id: nil, seq: i } }
      scheduler = instance_double(Ai::Autonomy::GoalDrivenSchedulerService)
      allow(scheduler).to receive(:next_action).and_return(*actions, nil)
      allow(Ai::Autonomy::GoalDrivenSchedulerService).to receive(:new).and_return(scheduler)

      results = service.execute_cycle

      expect(results[:decide].size).to eq(5)
      expect(results[:act].size).to eq(5)
      expect(results[:act].size).to eq(results[:decide].size)
    end

    it "acts on all actions when fewer than the cap are available" do
      actions = Array.new(3) { |i| { type: :evaluate_plan, plan_id: nil, seq: i } }
      scheduler = instance_double(Ai::Autonomy::GoalDrivenSchedulerService)
      allow(scheduler).to receive(:next_action).and_return(*actions, nil)
      allow(Ai::Autonomy::GoalDrivenSchedulerService).to receive(:new).and_return(scheduler)

      results = service.execute_cycle

      expect(results[:decide].size).to eq(3)
      expect(results[:act].size).to eq(3)
    end
  end

  # Goal-plan rulings 2 and 3. The paid call is stubbed at its boundary,
  # WorkerLlmClient#complete, and counted. Everything above it runs for real:
  # the classification, the bound, the scheduler's gates and the capability
  # matrix.
  describe "self-correct, the one replan door" do
    let!(:goal) do
      Ai::AgentGoal.create!(account: account, agent: agent, title: "Keep the lint queue empty",
                            description: "x", goal_type: "improvement", status: "active",
                            priority: 3, progress: 0.0)
    end
    let(:llm_calls) { [] }
    let(:plan_text) do
      "STEP: 1\nTYPE: observation\nDESCRIPTION: look again\nDEPENDS_ON: none\nEST_MINUTES: 1\nEST_COST: 0\n"
    end

    before do
      allow(WorkerJobService).to receive(:enqueue_ai_goal_plan_step_execution)
      calls = llm_calls
      text = plan_text
      allow_any_instance_of(WorkerLlmClient).to receive(:complete) do |*_args, **_kwargs|
        calls << 1
        Struct.new(:content, :cost).new(text, 0.0)
      end
    end

    def trusted!
      create(:ai_agent_trust_score, :trusted, account: account, agent: agent)
    end

    # An executing plan whose one step failed the way `kind` says, as the
    # internal door or the dispatch rescue would leave it.
    def failed_step_plan(kind:, version: 1)
      plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "executing", version: version)
      step = Ai::GoalPlanStep.create!(plan: plan, step_number: 1, status: "executing", step_type: "agent_execution")
      reason = kind == "no_dispatcher" ? "no dispatcher for step type agent_execution" : "enqueue failed: redis down"
      step.fail!(reason: reason, kind: kind)
      plan
    end

    # The same plan, concluded by the real evaluate step.
    def concluded_plan(kind:, version: 1)
      plan = failed_step_plan(kind: kind, version: version)
      service.send(:evaluate_plan_completion, plan)
      plan.reload
    end

    def decision_on(plan) = plan.reload.validation_result["self_correct"]

    it "concludes a deterministic failure as failed, fails the goal, and makes no model call" do
      trusted!
      plan = failed_step_plan(kind: "no_dispatcher")

      2.times { service.execute_cycle }

      expect(plan.reload.status).to eq("failed")
      expect(plan.validation_result).to include("failure_reason" => "no dispatcher for step type agent_execution",
                                                "failure_class" => "deterministic")
      expect(goal.reload.status).to eq("failed")
      expect(llm_calls).to be_empty
      expect(Ai::GoalPlan.for_goal(goal.id).count).to eq(1)
    end

    it "replans a transient failure exactly once" do
      trusted!
      plan = failed_step_plan(kind: "dispatch_raised")

      service.execute_cycle

      expect(llm_calls.size).to eq(1)
      replacement = Ai::GoalPlan.for_goal(goal.id).find_by(version: 2)
      expect(replacement.plan_data).to have_key("replan_context")
      expect(decision_on(plan)).to include("decision" => "replanned", "final" => true,
                                           "new_plan_id" => replacement.id)
      expect(goal.reload.metadata["replans_attempted"]).to eq(1)

      service.execute_cycle

      expect(llm_calls.size).to eq(1)
    end

    it "stops at the configured bound and fails the goal, naming the setting" do
      trusted!
      allow(SiteSetting).to receive(:get).and_call_original
      allow(SiteSetting).to receive(:get).with(described_class::MAX_REPLANS_SETTING).and_return("1")
      failed_step_plan(kind: "dispatch_raised")
      service.execute_cycle
      replacement = Ai::GoalPlan.for_goal(goal.id).find_by(version: 2)
      replacement.update!(status: "executing")
      replacement.steps.first.fail!(reason: "enqueue failed again", kind: "dispatch_raised")

      service.execute_cycle

      expect(llm_calls.size).to eq(1)
      expect(goal.reload.status).to eq("failed")
      expect(goal.metadata["failure_reason"]).to include("ai.autonomy.max_replans_per_goal")
      expect(decision_on(replacement)).to include("decision" => "bound_reached", "final" => true)
    end

    it "follows the setting when it is raised — the other arm" do
      trusted!
      allow(SiteSetting).to receive(:get).and_call_original
      allow(SiteSetting).to receive(:get).with(described_class::MAX_REPLANS_SETTING).and_return("2")
      failed_step_plan(kind: "dispatch_raised")
      service.execute_cycle
      replacement = Ai::GoalPlan.for_goal(goal.id).find_by(version: 2)
      replacement.update!(status: "executing")
      replacement.steps.first.fail!(reason: "enqueue failed again", kind: "dispatch_raised")

      service.execute_cycle

      expect(llm_calls.size).to eq(2)
      expect(goal.reload.status).to eq("active")
    end

    it "fails the goal with no model call when a transient failure arrives at the bound" do
      trusted!
      goal.update!(metadata: { "replans_attempted" => described_class::DEFAULT_MAX_REPLANS_PER_GOAL })
      plan = concluded_plan(kind: "dispatch_raised")

      service.execute_cycle

      expect(llm_calls).to be_empty
      expect(goal.reload.status).to eq("failed")
      expect(goal.metadata["failure_reason"]).to include(described_class::MAX_REPLANS_SETTING)
      expect(decision_on(plan)).to include("decision" => "bound_reached", "final" => true)
    end

    # Q3, with the REAL capability matrix: a supervised agent's tier denies
    # plan_and_execute.
    it "does not replan a supervised agent" do
      plan = concluded_plan(kind: "dispatch_raised")

      service.execute_cycle

      expect(llm_calls).to be_empty
      expect(decision_on(plan)).to include("decision" => "capability", "final" => false)
      expect(goal.reload.status).to eq("active")
    end

    it "does not replan while the kill switch is engaged, and replans once it is released" do
      trusted!
      plan = concluded_plan(kind: "dispatch_raised")
      user = create(:user, account: account)
      Ai::Autonomy::KillSwitchService.new(account: account).emergency_halt!(reason: "test", triggered_by: user)

      service.execute_cycle

      expect(llm_calls).to be_empty
      expect(decision_on(plan)).to include("decision" => "gate_halted", "final" => false)

      Ai::Autonomy::KillSwitchService.new(account: account).resume!(triggered_by: user)
      service.execute_cycle

      expect(llm_calls.size).to eq(1)
    end

    it "does not replan an agent whose budget is spent" do
      trusted!
      create(:ai_agent_budget, account: account, agent: agent, total_budget_cents: 100, spent_cents: 100)
      plan = concluded_plan(kind: "dispatch_raised")

      service.execute_cycle

      expect(llm_calls).to be_empty
      expect(decision_on(plan)).to include("decision" => "gate_no_budget", "final" => false)
    end

    it "does not replan an agent over its duty-cycle budget" do
      trusted!
      stub_const("Ai::Autonomy::DutyCycleService::MAX_DAILY_ACTIONS", 1)
      create(:ai_agent_execution, account: account, agent: agent, execution_context: { "kind" => "duty_cycle" })
      plan = concluded_plan(kind: "dispatch_raised")

      service.execute_cycle

      expect(llm_calls).to be_empty
      expect(decision_on(plan)).to include("decision" => "gate_duty_cycle", "final" => false)
    end
  end
end
