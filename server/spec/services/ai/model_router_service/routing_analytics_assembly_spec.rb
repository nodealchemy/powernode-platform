# frozen_string_literal: true

require "rails_helper"

# A task assembly (assemble_task) is persisted on ai_routing_decisions with
# request_type "task_assembly" and, once its run is reported, carries the run's
# cost. It is a record of WHAT a run was assembled from, not a routing choice,
# so the routing analytics (cost savings, recommendations) must not count it.
RSpec.describe Ai::ModelRouterService, "task assemblies in the routing analytics" do
  let(:account) { create(:account) }
  let(:analytics) { described_class.new(account: account) }

  def decision(request_type:, cost:, savings:)
    create(:ai_routing_decision, account: account, request_type: request_type, strategy_used: "hybrid",
                                 actual_cost_usd: cost, alternative_cost_usd: cost + savings, savings_usd: savings)
  end

  it "leaves task_assembly decisions out of the cost-savings analysis" do
    decision(request_type: "completion", cost: 1.0, savings: 0.5)
    decision(request_type: "task_assembly", cost: 9.0, savings: 4.0)

    result = analytics.analyze_cost_savings

    expect(result[:total_decisions]).to eq(1)
    expect(result[:total_actual_cost_usd]).to eq(1.0)
    expect(result[:total_savings_usd]).to eq(0.5)
  end

  it "returns no analysis when only assemblies exist" do
    decision(request_type: "task_assembly", cost: 9.0, savings: 4.0)

    expect(analytics.analyze_cost_savings).to be_nil
  end

  it "leaves them out of the optimization recommendations' sample" do
    10.times { decision(request_type: "task_assembly", cost: 1.0, savings: 0.0) }

    expect(analytics.get_optimization_recommendations).to eq([])
    expect(Ai::RoutingDecision.excluding_assemblies.count).to eq(0)
  end
end
