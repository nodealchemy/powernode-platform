# frozen_string_literal: true

require "rails_helper"

# IMP-2c41554c5cf1 — GoalDecompositionService#decompose creates the
# Ai::GoalPlan and then each Ai::GoalPlanStep with no transaction around them.
# GoalPlanStep validates step_type against STEP_TYPES, and step_type comes
# straight from the LLM's `TYPE:` line (#parse_plan_steps), so a model that
# echoes an invalid type back (the prompt literally shows
# "TYPE: agent_execution|observation|...") raises ActiveRecord::RecordInvalid
# on plan.steps.create!. #decompose's own `rescue StandardError` swallows
# that and returns nil (its documented failure contract — decompose_goal
# depends on it, see agent_autonomy_tool_decompose_goal_spec.rb), but the
# already-created GoalPlan — and any steps created before the bad one — were
# never rolled back: "error reported, side effect persisted." Worse, the
# draft plan consumes a version number (unique scoped to goal_id), so a
# caller's retry silently skips past the poisoned version.
RSpec.describe Ai::Autonomy::GoalDecompositionService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let!(:goal) do
    account.ai_agent_goals.create!(
      agent: agent, title: "stand up a staging cluster", goal_type: "improvement",
      status: "active", priority: 3
    )
  end

  subject(:service) { described_class.new(account: account) }

  # A valid step precedes the invalid one, so a partial write (plan + step 1
  # persisted, step 2's create! raises) would be visible if the create calls
  # aren't atomic.
  let(:llm_response) do
    {
      content: <<~PLAN,
        STEP: 1
        TYPE: agent_execution
        DESCRIPTION: Provision the staging compute stack
        DEPENDS_ON: none
        EST_MINUTES: 10
        EST_COST: 1.50
        STEP: 2
        TYPE: not_a_real_step_type
        DESCRIPTION: Do the second thing
        DEPENDS_ON: 1
        EST_MINUTES: 5
        EST_COST: 0.50
      PLAN
      cost_usd: 0.002
    }
  end

  before do
    expect_any_instance_of(described_class)
      .to receive(:call_llm)
      .with(hash_including(agent: agent))
      .and_return(llm_response)
  end

  it "returns nil (the documented failure contract callers depend on)" do
    expect(service.decompose(goal)).to be_nil
  end

  it "leaves no partial GoalPlan behind" do
    expect { service.decompose(goal) }.not_to change(Ai::GoalPlan, :count)
  end

  it "leaves no partial GoalPlanStep behind (step 1 would have been valid on its own)" do
    expect { service.decompose(goal) }.not_to change(Ai::GoalPlanStep, :count)
  end

  it "does not consume a version number for a future retry" do
    service.decompose(goal)

    expect(Ai::GoalPlan.for_goal(goal.id).maximum(:version)).to be_nil
  end
end
