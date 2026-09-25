# frozen_string_literal: true

require "rails_helper"

# IMP-9dd08c6e9a94 — decompose_goal's call site was DOA: it called
# GoalDecompositionService.new(account:, agent:) and #decompose(goal:,
# max_sub_goals:), but the real service only accepts #initialize(account:)
# and #decompose(goal) positional. Every call raised ArgumentError, caught
# by decompose_goal's own broad StandardError rescue, so the action always
# reported "Goal decomposition failed" no matter what the caller asked for.
# Drives the REAL service (not a stubbed .new — rspec-mocks' verifying
# partial double checks a stubbed .new's args against the real signature,
# so a stub matching the old broken call site would itself raise before
# and_return/and_raise ever fires); only the LLM call is stubbed, at the
# provider boundary (#call_llm), per the plan_composer/mission_composer
# convention (spec/services/ai/missions/mission_composer_spec.rb:30).
RSpec.describe "agent_autonomy MCP decompose_goal: real service integration" do
  let(:account) { create(:account) }
  let!(:actor) { create(:user, account: account, permissions: %w[ai.agents.read ai.goals.manage]) }
  let(:agent) { create(:ai_agent, account: account) }
  let!(:goal) do
    account.ai_agent_goals.create!(
      agent: agent, title: "stand up a staging cluster", goal_type: "improvement",
      status: "active", priority: 3
    )
  end

  def run
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.decompose_goal",
      params: { "goal_id" => goal.id },
      account: account,
      user: actor
    )
  end

  context "when the LLM returns a parseable plan" do
    before do
      # An expected call, not `allow`, and hash_including(agent: agent) pins
      # that the service resolves the agent from goal.agent (its own
      # #build_decomposition_context) — the OLD call site instead passed an
      # agent: kwarg straight into .new, which the real service doesn't
      # accept at all. Making this an expectation also means a regression
      # back to the pre-fix call site (which never reaches #call_llm — it
      # raises ArgumentError in .new/.decompose first) fails this example on
      # "expected call, received none" rather than silently passing.
      expect_any_instance_of(Ai::Autonomy::GoalDecompositionService)
        .to receive(:call_llm)
        .with(hash_including(agent: agent))
        .and_return(
          content: <<~PLAN,
            STEP: 1
            TYPE: agent_execution
            DESCRIPTION: Provision the staging compute stack
            DEPENDS_ON: none
            EST_MINUTES: 10
            EST_COST: 1.50
          PLAN
          cost_usd: 0.002
        )
    end

    it "calls through to the real service and returns an explicit plan hash (not the AR record)" do
      result = run

      expect(result[:success]).to be(true)
      data = result[:data]

      plan = Ai::GoalPlan.find(data[:plan_id])
      expect(plan.goal_id).to eq(goal.id)

      expect(data).to eq(
        plan_id: plan.id,
        goal_id: goal.id,
        plan_status: "draft",
        version: plan.version,
        estimated_cost_usd: plan.estimated_cost_usd,
        estimated_duration_minutes: plan.estimated_duration_minutes,
        steps: [
          {
            step_number: 1,
            step_type: "agent_execution",
            description: "Provision the staging compute stack",
            dependencies: []
          }
        ]
      )
    end
  end

  context "when the LLM call fails (GoalDecompositionService#decompose returns nil)" do
    before do
      expect_any_instance_of(Ai::Autonomy::GoalDecompositionService)
        .to receive(:call_llm)
        .with(hash_including(agent: agent))
        .and_return(nil)
    end

    it "returns a distinct error result rather than success_result(nil)" do
      result = run

      # A distinct message from the rescue arms' generic "Goal decomposition
      # failed" — deliberately, so this example cannot pass against the
      # pre-fix call site for the wrong reason (ArgumentError caught by the
      # generic StandardError rescue reads as success here too unless the
      # message differs).
      expect(result).to eq(success: false, error: "Goal decomposition produced no plan")
    end

    it "does not create a plan" do
      expect { run }.not_to change(Ai::GoalPlan, :count)
    end
  end
end
