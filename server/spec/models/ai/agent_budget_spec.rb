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

    it 'tracks when spent exceeds budget via exceeded?' do
      budget = create(:ai_agent_budget,
                      agent: agent,
                      account: account,
                      total_budget_cents: 1000,
                      spent_cents: 0)

      budget.update_columns(spent_cents: 1500)
      expect(budget.exceeded?).to be true
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
      result = budget.reserve!(3_000)
      expect(result).to be_truthy
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

    # reserve! is the guard that runs under the row lock. Its refusal must stop
    # the allocation outright, not fall through to child_budgets.create!.
    it 'creates no child and reserves nothing when reserve! refuses' do
      allow(budget).to receive(:reserve!).and_return(false)

      expect(budget.allocate_child(agent: child_agent, amount_cents: 3_000)).to be_nil
      expect(budget.child_budgets.reload).to be_empty
      expect(budget.reload.reserved_cents).to eq(0)
    end

    # Callers such as FactoryService#spawn already hold a transaction. A
    # refusal must still undo the child: an ActiveRecord::Rollback raised in a
    # JOINED transaction is swallowed there and the outer one commits.
    it 'leaves no child when reserve! refuses inside a caller\'s transaction' do
      allow(budget).to receive(:reserve!).and_return(false)

      result = Ai::AgentBudget.transaction do
        budget.allocate_child(agent: child_agent, amount_cents: 3_000)
      end

      expect(result).to be_nil
      expect(Ai::AgentBudget.where(parent_budget_id: budget.id)).to be_empty
    end

    # Two callers holding the same budget: the second one's in-memory
    # remaining_cents is stale. The lock-time check must decide, so the parent
    # is never over-allocated and the loser gets nil rather than an exception.
    it 'refuses a second allocation made through a stale copy of the parent' do
      stale = Ai::AgentBudget.find(budget.id)
      expect(budget.allocate_child(agent: child_agent, amount_cents: 6_000)).to be_persisted

      expect(stale.allocate_child(agent: child_agent, amount_cents: 6_000)).to be_nil
      expect(budget.reload.reserved_cents).to eq(6_000)
      expect(budget.child_budgets.count).to eq(1)
    end

    it 'allocates more than half of the remaining balance' do
      child_budget = budget.allocate_child(agent: child_agent, amount_cents: 8_000)

      expect(child_budget).to be_persisted
      expect(budget.reload.reserved_cents).to eq(8_000)
    end

    it 'refuses a zero or negative amount' do
      expect(budget.allocate_child(agent: child_agent, amount_cents: 0)).to be_nil
      expect(budget.allocate_child(agent: child_agent, amount_cents: -500)).to be_nil
      expect(budget.child_budgets.reload).to be_empty
      expect(budget.reload.reserved_cents).to eq(0)
    end
  end
  # IMP-05675d82db79 (dry-run campaign P0.2) — four call sites (context
  # injector budget line, governance resource-abuse remediation, budget
  # sensor payload, agent autonomy tool) invoked #allocated_cents, which
  # did not exist. It aliases total_budget_cents — the allocation IS the
  # total — including the WRITE path the governance remediation uses.
  describe 'allocated_cents alias' do
    let(:alias_budget) { create(:ai_agent_budget, account: account, agent: agent, total_budget_cents: 10_000) }

    it 'reads the total budget' do
      expect(alias_budget.allocated_cents).to eq(10_000)
    end

    it 'writes through update! (the governance halving path)' do
      alias_budget.update!(allocated_cents: (alias_budget.allocated_cents * 0.5).to_i)

      expect(alias_budget.reload.total_budget_cents).to eq(5_000)
    end
  end
end
