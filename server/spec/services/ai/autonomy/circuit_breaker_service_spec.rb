# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::CircuitBreakerService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account) }

  describe '#check' do
    it 'allows action when circuit is closed' do
      result = service.check(agent: agent, action_type: 'execute_tool')
      expect(result[:allowed]).to be true
      expect(result[:state]).to eq('closed')
    end

    it 'blocks action when circuit is open' do
      breaker = Ai::CircuitBreaker.create!(
        account: account, agent: agent, action_type: 'execute_tool',
        state: 'open', opened_at: 1.minute.ago, cooldown_seconds: 300
      )

      result = service.check(agent: agent, action_type: 'execute_tool')
      expect(result[:allowed]).to be false
      expect(result[:state]).to eq('open')
    end

    it 'allows action in half_open state' do
      Ai::CircuitBreaker.create!(
        account: account, agent: agent, action_type: 'execute_tool',
        state: 'half_open'
      )

      result = service.check(agent: agent, action_type: 'execute_tool')
      expect(result[:allowed]).to be true
      expect(result[:state]).to eq('half_open')
    end

    it 'transitions from open to half_open when cooldown expires' do
      Ai::CircuitBreaker.create!(
        account: account, agent: agent, action_type: 'execute_tool',
        state: 'open', opened_at: 10.minutes.ago, cooldown_seconds: 300
      )

      result = service.check(agent: agent, action_type: 'execute_tool')
      expect(result[:state]).to eq('half_open')
      expect(result[:allowed]).to be true
    end
  end

  describe '#record_failure' do
    it 'increments failure count' do
      service.record_failure(agent: agent, action_type: 'test')
      breaker = Ai::CircuitBreaker.find_by(agent_id: agent.id, action_type: 'test')
      expect(breaker.failure_count).to eq(1)
    end

    it 'trips breaker when threshold reached' do
      breaker = Ai::CircuitBreaker.create!(
        account: account, agent: agent, action_type: 'test',
        state: 'closed', failure_count: 4, failure_threshold: 5
      )

      service.record_failure(agent: agent, action_type: 'test')
      expect(breaker.reload.state).to eq('open')
    end

    it 'trips immediately during half_open' do
      Ai::CircuitBreaker.create!(
        account: account, agent: agent, action_type: 'test',
        state: 'half_open', failure_count: 0
      )

      service.record_failure(agent: agent, action_type: 'test')
      breaker = Ai::CircuitBreaker.find_by(agent_id: agent.id, action_type: 'test')
      expect(breaker.state).to eq('open')
    end
  end

  describe '#record_success' do
    it 'closes breaker when success threshold reached in half_open' do
      Ai::CircuitBreaker.create!(
        account: account, agent: agent, action_type: 'test',
        state: 'half_open', success_count: 2, success_threshold: 3
      )

      service.record_success(agent: agent, action_type: 'test')
      breaker = Ai::CircuitBreaker.find_by(agent_id: agent.id, action_type: 'test')
      expect(breaker.state).to eq('closed')
    end
  end

  describe '#reset!' do
    it 'closes the circuit breaker' do
      breaker = Ai::CircuitBreaker.create!(
        account: account, agent: agent, action_type: 'test',
        state: 'open', failure_count: 10, opened_at: Time.current
      )

      service.reset!(breaker)
      expect(breaker.reload.state).to eq('closed')
      expect(breaker.failure_count).to eq(0)
    end
  end
end
