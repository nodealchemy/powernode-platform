# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::BudgetAwareContextService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account) }

  describe '#generate_context' do
    context 'with no budget' do
      it 'returns NONE regime' do
        result = service.generate_context(agent: agent)
        expect(result[:regime]).to eq('NONE')
      end
    end

    context 'with low utilization budget' do
      let!(:budget) do
        create(:ai_agent_budget, account: account, agent: agent,
               total_budget_cents: 10000, spent_cents: 2000)
      end

      it 'returns NORMAL regime (low utilization = healthy availability)' do
        result = service.generate_context(agent: agent)
        expect(result[:regime]).to eq('NORMAL')
        expect(result[:utilization_pct]).to eq(20.0)
      end
    end

    context 'with high utilization budget' do
      let!(:budget) do
        create(:ai_agent_budget, account: account, agent: agent,
               total_budget_cents: 10000, spent_cents: 9200)
      end

      it 'returns CRITICAL regime' do
        result = service.generate_context(agent: agent)
        expect(result[:regime]).to eq('CRITICAL')
        expect(result[:context]).to include('CRITICAL')
      end
    end
  end

  describe '#check_rate_of_change' do
    let!(:budget) do
      create(:ai_agent_budget, account: account, agent: agent,
             total_budget_cents: 10000, spent_cents: 5000,
             period_start: 10.days.ago, period_end: 20.days.from_now)
    end

    it 'calculates velocity rate' do
      result = service.check_rate_of_change(agent, budget)
      expect(result[:rate]).to be_a(Float)
      expect(result).to have_key(:alert)
    end
  end
end
