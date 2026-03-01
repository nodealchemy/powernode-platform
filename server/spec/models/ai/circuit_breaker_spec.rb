# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::CircuitBreaker, type: :model do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  describe 'validations' do
    subject { build(:ai_circuit_breaker, account: account, agent: agent) }

    it { is_expected.to be_valid }

    it 'validates state inclusion' do
      subject.state = 'invalid'
      expect(subject).not_to be_valid
    end

    it 'validates action_type uniqueness per agent' do
      create(:ai_circuit_breaker, account: account, agent: agent, action_type: 'test')
      dup = build(:ai_circuit_breaker, account: account, agent: agent, action_type: 'test')
      expect(dup).not_to be_valid
    end
  end

  describe '#cooldown_expired?' do
    let(:breaker) { create(:ai_circuit_breaker, account: account, agent: agent, state: 'open', cooldown_seconds: 300) }

    it 'returns false when recently opened' do
      breaker.update!(opened_at: 1.minute.ago)
      expect(breaker.cooldown_expired?).to be false
    end

    it 'returns true when cooldown has passed' do
      breaker.update!(opened_at: 10.minutes.ago)
      expect(breaker.cooldown_expired?).to be true
    end

    it 'returns false when closed' do
      breaker.update!(state: 'closed')
      expect(breaker.cooldown_expired?).to be false
    end
  end

  describe '#trip!' do
    let(:breaker) { create(:ai_circuit_breaker, account: account, agent: agent, state: 'closed') }

    it 'transitions to open state' do
      breaker.trip!
      expect(breaker.reload.state).to eq('open')
      expect(breaker.opened_at).to be_present
    end

    it 'records transition in history' do
      breaker.trip!
      expect(breaker.reload.history.last['to_state']).to eq('open')
    end
  end

  describe '#close!' do
    let(:breaker) { create(:ai_circuit_breaker, account: account, agent: agent, state: 'open', failure_count: 5) }

    it 'transitions to closed and resets failure count' do
      breaker.close!
      expect(breaker.reload.state).to eq('closed')
      expect(breaker.failure_count).to eq(0)
    end
  end
end
