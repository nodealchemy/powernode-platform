# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowCircuitBreakerService do
  include ActiveSupport::Testing::TimeHelpers

  let(:service_name) { 'test_service' }
  let(:config) do
    {
      failure_threshold: 5,
      success_threshold: 3,
      timeout_duration: 60_000 # milliseconds
    }
  end

  subject(:circuit_breaker) { described_class.new(service_name: service_name, config: config) }

  before do
    # Clear Rails cache state before each test
    Rails.cache.delete("circuit_breaker:#{service_name}")
  end

  describe '#execute' do
    context 'when circuit is closed' do
      it 'executes the block successfully' do
        result = circuit_breaker.execute { 'success' }
        expect(result).to eq('success')
      end

      it 'increments success count on successful execution' do
        circuit_breaker.execute { 'success' }
        stats = circuit_breaker.stats
        expect(stats[:success_count]).to eq(1)
      end

      it 'increments failure count on exception' do
        expect {
          circuit_breaker.execute { raise StandardError, 'test error' }
        }.to raise_error(StandardError)

        stats = circuit_breaker.stats
        expect(stats[:failure_count]).to eq(1)
      end

      it 'transitions to open when failure threshold reached' do
        config[:failure_threshold].times do
          begin
            circuit_breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end

        expect(circuit_breaker.state).to eq('open')
      end

      it 'resets consecutive failures after successful execution' do
        3.times do
          begin
            circuit_breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end

        circuit_breaker.execute { 'success' }
        stats = circuit_breaker.stats
        # Note: failure_count is cumulative, consecutive_failures resets
        expect(stats[:consecutive_failures]).to eq(0)
      end
    end

    context 'when circuit is open' do
      before do
        # Trip the circuit
        config[:failure_threshold].times do
          begin
            circuit_breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end
      end

      it 'raises CircuitOpenError without executing block' do
        expect {
          circuit_breaker.execute { 'should not execute' }
        }.to raise_error(AiWorkflowCircuitBreakerService::CircuitOpenError)
      end

      it 'does not execute the block when open' do
        executed = false
        begin
          circuit_breaker.execute { executed = true }
        rescue AiWorkflowCircuitBreakerService::CircuitOpenError
          # Expected
        end

        expect(executed).to be false
      end

      it 'transitions to half_open after timeout period' do
        timeout_seconds = config[:timeout_duration] / 1000
        travel(timeout_seconds + 1) do
          circuit_breaker.execute { 'success' }
          # After executing in half_open, it needs success_threshold successes
          # One success alone won't close it
          expect(circuit_breaker.state).to eq('half_open')
        end
      end

      it 'records circuit open events' do
        begin
          circuit_breaker.execute { 'test' }
        rescue AiWorkflowCircuitBreakerService::CircuitOpenError => e
          expect(e.message).to include('Circuit breaker is open')
          expect(e.message).to include(service_name)
        end
      end
    end

    context 'when circuit is half_open' do
      before do
        # Trip circuit to open
        config[:failure_threshold].times do
          begin
            circuit_breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end

        # Move time forward to enter half_open
        timeout_seconds = config[:timeout_duration] / 1000
        travel(timeout_seconds + 1)
      end

      after do
        travel_back
      end

      it 'allows execution in half_open state' do
        first_call = circuit_breaker.execute { 'test1' }
        expect(first_call).to eq('test1')
        expect(circuit_breaker.state).to eq('half_open')
      end

      it 'transitions to closed after success threshold met' do
        config[:success_threshold].times do
          circuit_breaker.execute { 'success' }
        end

        expect(circuit_breaker.state).to eq('closed')
      end

      it 'transitions back to open on failure' do
        expect {
          circuit_breaker.execute { raise StandardError }
        }.to raise_error(StandardError)

        expect(circuit_breaker.state).to eq('open')
      end

      it 'resets consecutive successes on transition to closed' do
        config[:success_threshold].times do
          circuit_breaker.execute { 'success' }
        end

        stats = circuit_breaker.stats
        expect(stats[:consecutive_successes]).to eq(0)
        expect(stats[:state]).to eq('closed')
      end

      it 'increments consecutive success count for each successful call' do
        2.times { circuit_breaker.execute { 'success' } }

        stats = circuit_breaker.stats
        expect(stats[:consecutive_successes]).to eq(2)
      end
    end
  end

  describe '#state' do
    it 'returns closed by default' do
      expect(circuit_breaker.state).to eq('closed')
    end

    it 'persists state in cache' do
      config[:failure_threshold].times do
        begin
          circuit_breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      # Create new instance to verify persistence
      new_breaker = described_class.new(service_name: service_name, config: config)
      expect(new_breaker.state).to eq('open')
    end

    it 'returns current state from cache' do
      Rails.cache.write("circuit_breaker:#{service_name}", {
        state: 'half_open',
        failure_count: 0,
        success_count: 0,
        consecutive_failures: 0,
        consecutive_successes: 0,
        last_failure_time: Time.current,
        state_changed_at: Time.current
      })
      new_breaker = described_class.new(service_name: service_name, config: config)
      expect(new_breaker.state).to eq('half_open')
    end
  end

  describe '#stats' do
    it 'returns comprehensive statistics' do
      stats = circuit_breaker.stats

      expect(stats).to include(
        state: 'closed',
        failure_count: 0,
        success_count: 0,
        consecutive_failures: 0,
        consecutive_successes: 0
      )
      expect(stats[:config]).to include(
        failure_threshold: 5,
        success_threshold: 3
      )
    end

    it 'includes last failure time when available' do
      begin
        circuit_breaker.execute { raise StandardError }
      rescue StandardError
        # Expected
      end

      stats = circuit_breaker.stats
      expect(stats[:last_failure_time]).to be_present
    end

    it 'includes time until retry when circuit is open' do
      config[:failure_threshold].times do
        begin
          circuit_breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      stats = circuit_breaker.stats
      expect(stats[:next_retry_at]).to be_present
    end

    it 'does not include retry time when circuit is closed' do
      stats = circuit_breaker.stats
      expect(stats[:next_retry_at]).to be_nil
    end

    it 'tracks total successful and failed calls' do
      3.times { circuit_breaker.execute { 'success' } }
      2.times do
        begin
          circuit_breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      stats = circuit_breaker.stats
      expect(stats[:success_count]).to eq(3)
      expect(stats[:failure_count]).to eq(2)
    end
  end

  describe '#reset!' do
    before do
      # Trip the circuit
      config[:failure_threshold].times do
        begin
          circuit_breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end
    end

    it 'resets circuit to closed state' do
      circuit_breaker.reset!
      expect(circuit_breaker.state).to eq('closed')
    end

    it 'clears failure count' do
      circuit_breaker.reset!
      stats = circuit_breaker.stats
      expect(stats[:failure_count]).to eq(0)
    end

    it 'clears success count' do
      circuit_breaker.reset!
      stats = circuit_breaker.stats
      expect(stats[:success_count]).to eq(0)
    end

    it 'removes last failure time' do
      circuit_breaker.reset!
      stats = circuit_breaker.stats
      expect(stats[:last_failure_time]).to be_nil
    end

    it 'allows execution after reset' do
      circuit_breaker.reset!
      result = circuit_breaker.execute { 'success after reset' }
      expect(result).to eq('success after reset')
    end
  end

  describe 'error handling' do
    it 'propagates exceptions while recording failures' do
      expect {
        circuit_breaker.execute { raise ArgumentError, 'custom error' }
      }.to raise_error(ArgumentError, 'custom error')

      stats = circuit_breaker.stats
      expect(stats[:failure_count]).to eq(1)
    end

    it 'handles network timeout errors' do
      expect {
        circuit_breaker.execute { raise Timeout::Error }
      }.to raise_error(Timeout::Error)

      stats = circuit_breaker.stats
      expect(stats[:failure_count]).to eq(1)
    end

    it 'handles connection errors' do
      expect {
        circuit_breaker.execute { raise Errno::ECONNREFUSED }
      }.to raise_error(Errno::ECONNREFUSED)

      stats = circuit_breaker.stats
      expect(stats[:failure_count]).to eq(1)
    end

    it 'records last failure time' do
      begin
        circuit_breaker.execute { raise ArgumentError, 'test' }
      rescue ArgumentError
        # Expected
      end

      stats = circuit_breaker.stats
      expect(stats[:last_failure_time]).to be_present
    end
  end

  describe 'configuration inheritance' do
    context 'with default configuration' do
      subject(:default_breaker) { described_class.new(service_name: 'default_service') }

      before { Rails.cache.delete('circuit_breaker:default_service') }

      it 'uses default failure threshold' do
        stats = default_breaker.stats
        expect(stats[:config][:failure_threshold]).to eq(5)
      end

      it 'uses default success threshold' do
        stats = default_breaker.stats
        expect(stats[:config][:success_threshold]).to eq(2)
      end

      it 'uses default timeout duration' do
        stats = default_breaker.stats
        expect(stats[:config][:timeout_duration]).to eq(60_000)
      end
    end

    context 'with custom configuration' do
      let(:custom_config) do
        {
          failure_threshold: 10,
          success_threshold: 5,
          timeout_duration: 120_000
        }
      end

      subject(:custom_breaker) { described_class.new(service_name: 'custom_service', config: custom_config) }

      before { Rails.cache.delete('circuit_breaker:custom_service') }

      it 'uses custom thresholds' do
        stats = custom_breaker.stats
        expect(stats[:config][:failure_threshold]).to eq(10)
        expect(stats[:config][:success_threshold]).to eq(5)
        expect(stats[:config][:timeout_duration]).to eq(120_000)
      end
    end
  end

  describe 'concurrent access' do
    it 'handles multiple threads safely' do
      threads = 10.times.map do
        Thread.new do
          circuit_breaker.execute { 'concurrent' }
        end
      end

      threads.each(&:join)
      stats = circuit_breaker.stats
      expect(stats[:success_count]).to be >= 10
    end

    it 'maintains consistent state across threads' do
      threads = config[:failure_threshold].times.map do |_i|
        Thread.new do
          begin
            circuit_breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end
      end

      threads.each(&:join)
      expect(circuit_breaker.state).to eq('open')
    end
  end

  describe 'cache persistence' do
    it 'survives service restarts' do
      # Trip circuit
      config[:failure_threshold].times do
        begin
          circuit_breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      # Simulate restart with new instance
      new_instance = described_class.new(service_name: service_name, config: config)
      expect(new_instance.state).to eq('open')
    end

    it 'maintains counters across instances' do
      3.times do
        begin
          circuit_breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      new_instance = described_class.new(service_name: service_name, config: config)
      stats = new_instance.stats
      expect(stats[:failure_count]).to eq(3)
    end
  end

  describe '#open! and #close!' do
    it 'allows force opening the circuit' do
      circuit_breaker.open!
      expect(circuit_breaker.state).to eq('open')
    end

    it 'allows force closing the circuit' do
      circuit_breaker.open!
      circuit_breaker.close!
      expect(circuit_breaker.state).to eq('closed')
    end
  end
end
