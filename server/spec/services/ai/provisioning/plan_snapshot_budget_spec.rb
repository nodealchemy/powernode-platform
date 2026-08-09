# frozen_string_literal: true

require "rails_helper"

# F7 (IMP 019fe4c5-2e24): the brief carries budget_cap_usd_monthly and the
# snapshot carries a cost estimate — and nothing ever compared them. Observed
# at both operator gates: a $5/mo cap met a $42 (run b) and $168 (run c)
# estimate with no flag anywhere in the approval payload. The snapshot now
# surfaces the comparison so the approver — and P2's auto-approver — sees the
# overage as a first-class field.
RSpec.describe Ai::Provisioning::PlanSnapshotService, "budget surfacing", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, status: "active") }
  let(:goal) do
    Ai::AgentGoal.create!(account: account, agent: agent, title: "G", goal_type: "creation",
                          status: "pending", priority: 3, progress: 0.0, success_criteria: {})
  end
  let(:plan) do
    Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                         status: "draft", version: 1, plan_data: {})
  end

  subject(:service) { described_class.new(account: account) }

  def add_step!(brief)
    plan.steps.create!(
      step_number: 1, step_type: "provisioning_skill", description: "provision",
      execution_config: { "skill" => "provision_full_stack",
                          "inputs" => { "count" => 1, "brief" => brief } }
    )
  end

  before do
    allow(service).to receive(:build_cost_estimate).and_return(
      { monthly_usd: 42.0, one_time_usd: 0.0, by_resource: [], confidence: "med" }
    )
  end

  it "flags an estimate exceeding the brief's cap" do
    add_step!("budget_cap_usd_monthly" => 5.0)
    budget = service.snapshot(plan: plan)[:budget]

    expect(budget[:cap_usd_monthly]).to eq(5.0)
    expect(budget[:estimate_usd_monthly]).to eq(42.0)
    expect(budget[:within_budget]).to be false
    expect(budget[:overage_usd_monthly]).to eq(37.0)
  end

  it "reports within_budget when the estimate fits" do
    add_step!("budget_cap_usd_monthly" => 100.0)
    budget = service.snapshot(plan: plan)[:budget]

    expect(budget[:within_budget]).to be true
    expect(budget[:overage_usd_monthly]).to eq(0.0)
  end

  it "omits the budget block when the brief carries no cap" do
    add_step!({})
    expect(service.snapshot(plan: plan)[:budget]).to be_nil
  end
end
