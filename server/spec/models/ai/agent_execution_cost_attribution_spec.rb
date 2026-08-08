# frozen_string_literal: true

require "rails_helper"

# IMP-affe7f6816e8 (dry-run campaign 019fdffd-aeed, P0.1) — cost attribution.
# calculate_cost and propagate_cost_to_budget both called agent.model, which
# does not exist (Ai::Agent defines resolved_model). Consequences whenever
# output_data lacks "model_used":
#   - calculate_cost raised NoMethodError into its caller's fallback → $0.00
#   - propagate_cost_to_budget raised while BUILDING the debit metadata, its
#     blanket rescue swallowed it, and the budget was NEVER debited at all —
#     every execution with a budget ran free.
# No hardcoded model names: the expected model is whatever the agent's own
# provider resolution yields, and pricing is stubbed keyed on that value.
RSpec.describe Ai::AgentExecution, "cost attribution" do
  let(:account)  { create(:account) }
  let(:user)     { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:agent)    { create(:ai_agent, account: account, provider: provider, creator: user, status: "active") }

  let(:execution) do
    create(:ai_agent_execution, account: account, agent: agent,
           output_data: {}) # no "model_used" — the fallback path under test
  end

  let(:resolved) { agent.resolved_model }

  before do
    expect(resolved).to be_present # sanity: the factory provider resolves a model
    allow(Ai::Autonomy::PricingSyncService).to receive(:pricing_for).and_return(nil)
    allow(Ai::Autonomy::PricingSyncService).to receive(:pricing_for)
      .with(resolved.to_s).and_return({ "input" => 1.0, "output" => 2.0 })
  end

  describe "#calculate_cost fallback (no model_used in output_data)" do
    it "resolves the agent's model and records a nonzero cost" do
      cost = execution.send(:calculate_cost, 1_000)

      expect(cost).to be > 0.0
    end
  end

  describe "#propagate_cost_to_budget" do
    let!(:budget) { create(:ai_agent_budget, account: account, agent: agent) }

    it "debits the real cents and stamps the resolved model in the transaction metadata" do
      execution.update_columns(cost_usd: 0.5)

      execution.send(:propagate_cost_to_budget)

      txn = budget.budget_transactions.order(:created_at).last
      expect(txn).not_to be_nil
      expect(txn.amount_cents).to eq(50)
      expect(txn.metadata["model"]).to eq(resolved)
      expect(budget.reload.spent_cents).to eq(50)
    end
  end
end
