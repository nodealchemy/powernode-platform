# frozen_string_literal: true

require "rails_helper"

# Regression: the budget-overrun check in GoalProgressSensor#collect iterates
# every executing GoalPlan and, inside the loop, re-ran
# `Ai::AgentBudget.where(agent_id: agent.id).active.first`. That query is keyed
# only on agent.id (never on `plan`) — it is loop-invariant, so it fired one
# identical DB query per plan where one suffices. The budget lookup must run
# ONCE regardless of the number of executing plans, and behavior (per-plan
# observations) must be identical.
RSpec.describe Ai::Autonomy::Sensors::GoalProgressSensor, type: :service do
  subject(:sensor) { described_class.new(account: account, agent: agent) }

  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  describe "#collect budget-overrun check" do
    # Two executing plans for the same agent, each with a cost high enough to
    # trip the "budget may be insufficient" branch (remaining 100.00 <
    # estimated_cost * 100 * 0.5 = 15_000 cents).
    let!(:budget) do
      create(:ai_agent_budget, account: account, agent: agent,
                               total_budget_cents: 10_000, spent_cents: 0, reserved_cents: 0)
    end

    before do
      2.times do |i|
        goal = Ai::AgentGoal.create!(
          account: account, agent: agent,
          title: "Goal #{i}", description: "x",
          goal_type: "creation", status: "active", priority: 3, progress: 0.0
        )
        Ai::GoalPlan.create!(
          account: account, goal: goal, agent: agent,
          status: "executing", estimated_cost_usd: 300, version: 1
        )
      end
    end

    it "queries AgentBudget only once across multiple executing plans" do
      expect(Ai::AgentBudget).to receive(:where).with(agent_id: agent.id).once.and_call_original

      sensor.collect
    end

    it "still emits one budget-overrun observation per plan (behavior unchanged)" do
      observations = sensor.collect
      budget_obs = observations.select { |o| o[:observation_type] == "alert" }

      expect(budget_obs.size).to eq(2)
      expect(budget_obs.map { |o| o[:data][:estimated_cost] }).to all(eq(300))
      expect(budget_obs.map { |o| o[:data][:remaining_budget] }).to all(eq(100.0))
    end
  end
end
