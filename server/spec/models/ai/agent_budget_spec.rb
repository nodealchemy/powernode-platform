# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentBudget, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:agent).class_name('Ai::Agent') }
    it { should belong_to(:parent_budget).class_name('Ai::AgentBudget').optional }
    it { should have_many(:child_budgets).class_name('Ai::AgentBudget') }
  end

  describe 'validations' do
    it { should validate_presence_of(:total_budget_cents) }
    it { should validate_numericality_of(:total_budget_cents).is_greater_than(0) }
    it { should validate_numericality_of(:spent_cents).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:reserved_cents).is_greater_than_or_equal_to(0) }
    it { should validate_inclusion_of(:currency).in_array(%w[USD EUR GBP]) }
    it { should validate_inclusion_of(:period_type).in_array(%w[daily weekly monthly total]) }

    it 'is invalid when spent exceeds budget' do
      budget = build(:ai_agent_budget,
                     agent: agent,
                     account: account,
                     total_budget_cents: 1000,
                     spent_cents: 1500)

      expect(budget).not_to be_valid
      expect(budget.errors[:spent_cents]).to include('cannot exceed total budget')
    end
  end

  describe '#remaining_cents' do
    it 'returns total minus spent minus reserved' do
      budget = create(:ai_agent_budget,
                      agent: agent,
                      account: account,
                      total_budget_cents: 10_000,
                      spent_cents: 3_000,
                      reserved_cents: 2_000)

      expect(budget.remaining_cents).to eq(5_000)
    end
  end

  describe '#utilization_percentage' do
    it 'returns the percentage of budget spent' do
      budget = create(:ai_agent_budget,
                      agent: agent,
                      account: account,
                      total_budget_cents: 10_000,
                      spent_cents: 2_500)

      expect(budget.utilization_percentage).to eq(25.0)
    end

    it 'returns 0 when total_budget_cents is zero' do
      budget = build(:ai_agent_budget,
                     agent: agent,
                     account: account,
                     total_budget_cents: 1) # Can't be 0 due to validation

      budget.total_budget_cents = 0 # bypass for test
      expect(budget.utilization_percentage).to eq(0)
    end
  end

  describe '#exceeded?' do
    it 'returns true when spent equals total budget' do
      budget = create(:ai_agent_budget, :exceeded,
                      agent: agent,
                      account: account)

      expect(budget.exceeded?).to be true
    end

    it 'returns false when spent is below total budget' do
      budget = create(:ai_agent_budget,
                      agent: agent,
                      account: account,
                      total_budget_cents: 10_000,
                      spent_cents: 5_000)

      expect(budget.exceeded?).to be false
    end
  end

  describe '#reserve!' do
    let(:budget) do
      create(:ai_agent_budget,
             agent: agent,
             account: account,
             total_budget_cents: 10_000,
             spent_cents: 0,
             reserved_cents: 0)
    end

    it 'increments reserved_cents by the given amount' do
      expect(budget.reserve!(3_000)).to be true
      expect(budget.reload.reserved_cents).to eq(3_000)
    end

    it 'returns false when insufficient remaining budget' do
      budget.update_columns(spent_cents: 9_000)
      expect(budget.reserve!(2_000)).to be false
    end

    it 'allows multiple reservations within budget' do
      budget.reserve!(3_000)
      budget.reserve!(2_000)
      expect(budget.reload.reserved_cents).to eq(5_000)
    end
  end

  describe '#spend!' do
    let(:budget) do
      create(:ai_agent_budget,
             agent: agent,
             account: account,
             total_budget_cents: 10_000,
             spent_cents: 0,
             reserved_cents: 3_000)
    end

    it 'decrements reserved_cents and increments spent_cents' do
      budget.spend!(2_000)
      budget.reload

      expect(budget.spent_cents).to eq(2_000)
      expect(budget.reserved_cents).to eq(1_000)
    end

    it 'does not allow reserved_cents to go negative' do
      budget.spend!(5_000)
      budget.reload

      expect(budget.reserved_cents).to eq(0)
      expect(budget.spent_cents).to eq(5_000)
    end
  end

  describe '#release_reservation!' do
    let(:budget) do
      create(:ai_agent_budget,
             agent: agent,
             account: account,
             total_budget_cents: 10_000,
             reserved_cents: 3_000)
    end

    it 'decrements reserved_cents by the given amount' do
      budget.release_reservation!(2_000)
      expect(budget.reload.reserved_cents).to eq(1_000)
    end

    it 'does not allow reserved_cents to go negative' do
      budget.release_reservation!(5_000)
      expect(budget.reload.reserved_cents).to eq(0)
    end
  end

  describe '#allocate_child' do
    let(:child_agent) { create(:ai_agent, account: account, creator: user, provider: provider) }
    let(:budget) do
      create(:ai_agent_budget,
             agent: agent,
             account: account,
             total_budget_cents: 10_000,
             spent_cents: 0,
             reserved_cents: 0)
    end

    it 'creates a child budget' do
      child_budget = budget.allocate_child(agent: child_agent, amount_cents: 3_000)

      expect(child_budget).to be_persisted
      expect(child_budget.total_budget_cents).to eq(3_000)
      expect(child_budget.parent_budget).to eq(budget)
      expect(child_budget.agent).to eq(child_agent)
      expect(child_budget.account).to eq(account)
    end

    it 'reserves the amount in the parent budget' do
      budget.allocate_child(agent: child_agent, amount_cents: 3_000)
      expect(budget.reload.reserved_cents).to eq(3_000)
    end

    it 'returns nil when insufficient remaining budget' do
      budget.update_columns(spent_cents: 9_000)
      result = budget.allocate_child(agent: child_agent, amount_cents: 3_000)
      expect(result).to be_nil
    end

    it 'inherits currency from parent' do
      child_budget = budget.allocate_child(agent: child_agent, amount_cents: 3_000)
      expect(child_budget.currency).to eq(budget.currency)
    end
  end
end
