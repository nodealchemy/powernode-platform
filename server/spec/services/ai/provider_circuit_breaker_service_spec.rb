# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ProviderCircuitBreakerService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:mock_redis) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(mock_redis).to receive(:get).and_return(nil)
    allow(mock_redis).to receive(:set)
    allow(mock_redis).to receive(:expire)
  end

  subject(:breaker) { described_class.new(provider) }

  describe '#initialize' do
    it 'sets up circuit breaker with provider-specific config' do
      expect(breaker.provider).to eq(provider)
    end

    it 'initializes in closed state' do
      expect(breaker.circuit_state).to eq(:closed)
    end
  end

  describe '#call' do
    it 'executes the block when circuit is closed' do
      result = breaker.call { "success" }
      expect(result).to eq("success")
    end

    it 'raises CircuitBreakerOpenError when circuit is open' do
      breaker.force_open!

      expect { breaker.call { "test" } }.to raise_error(
        Ai::ProviderCircuitBreakerService::CircuitBreakerOpenError
      )
    end

    it 'records failures and opens circuit after threshold' do
      5.times do
        begin
          breaker.call { raise StandardError, "provider error" }
        rescue StandardError
          # expected
        end
      end

      expect(breaker.circuit_state).to eq(:open)
    end

    it 'records successes in half-open state to close circuit' do
      # Open the circuit
      breaker.force_open!

      # Simulate timeout elapsed by manipulating state
      breaker.instance_variable_set(:@last_failure_time, 2.minutes.ago)
      breaker.instance_variable_set(:@state, "half_open")
      allow(mock_redis).to receive(:set)
      allow(mock_redis).to receive(:expire)

      # Two successes needed (success_threshold: 2)
      breaker.call { "ok" }
      breaker.call { "ok" }

      expect(breaker.circuit_state).to eq(:closed)
    end
  end

  describe '#provider_available?' do
    it 'returns true when circuit is closed' do
      expect(breaker.provider_available?).to be true
    end

    it 'returns false when circuit is open' do
      breaker.force_open!
      expect(breaker.provider_available?).to be false
    end
  end

  describe '#circuit_stats' do
    it 'includes provider-specific information' do
      stats = breaker.circuit_stats

      expect(stats[:provider_id]).to eq(provider.id)
      expect(stats[:provider_name]).to eq(provider.name)
      expect(stats).to have_key(:can_attempt)
      expect(stats).to have_key(:state)
      expect(stats).to have_key(:failure_count)
    end
  end

  describe '#reset_circuit' do
    it 'resets to closed state' do
      breaker.force_open!
      breaker.reset_circuit

      expect(breaker.circuit_state).to eq(:closed)
    end
  end

  describe '#failure_count' do
    it 'returns 0 initially' do
      expect(breaker.failure_count).to eq(0)
    end

    it 'increments after failures' do
      begin
        breaker.call { raise StandardError, "error" }
      rescue StandardError
        # expected
      end

      expect(breaker.failure_count).to be >= 1
    end
  end

  describe '#last_failure_time' do
    it 'is nil initially' do
      expect(breaker.last_failure_time).to be_nil
    end
  end

  describe '#time_until_retry' do
    it 'returns 0 when circuit is closed' do
      expect(breaker.time_until_retry).to eq(0)
    end
  end

  describe '.all_provider_stats' do
    it 'returns stats for all active providers' do
      provider  # ensure created
      create(:ai_provider, account: account)

      stats = described_class.all_provider_stats

      expect(stats.size).to eq(Ai::Provider.active.count)
      stats.each do |stat|
        expect(stat).to have_key(:provider_id)
        expect(stat).to have_key(:state)
      end
    end
  end

  describe '.reset_all_circuits' do
    it 'resets all provider circuit breakers' do
      provider  # ensure created
      create(:ai_provider, account: account)

      expect { described_class.reset_all_circuits }.not_to raise_error
    end
  end

  describe 'on_state_change callback' do
    context 'when circuit opens and provider has an account' do
      before do
        allow(provider).to receive(:account).and_return(account)
        allow(Ai::SelfHealing::RemediationDispatcher).to receive(:dispatch)
      end

      it 'dispatches remediation when circuit opens' do
        5.times do
          begin
            breaker.call { raise StandardError, "provider down" }
          rescue StandardError
            # expected
          end
        end

        expect(Ai::SelfHealing::RemediationDispatcher).to have_received(:dispatch).with(
          hash_including(
            account: account,
            trigger_event: "circuit_breaker_opened"
          )
        )
      end
    end

    context 'when remediation dispatch fails' do
      before do
        allow(provider).to receive(:account).and_return(account)
        allow(Ai::SelfHealing::RemediationDispatcher).to receive(:dispatch).and_raise(StandardError, "dispatch error")
      end

      it 'logs the error and does not re-raise' do
        expect(Rails.logger).to receive(:error).at_least(:once)

        5.times do
          begin
            breaker.call { raise StandardError, "provider down" }
          rescue StandardError
            # expected
          end
        end
      end
    end
  end
end
