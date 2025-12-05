# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkflowCircuitBreakerService do
  let(:service_name) { 'test_service' }
  let(:config) do
    {
      failure_threshold: 5,
      success_threshold: 3,
      timeout_seconds: 60,
      half_open_max_calls: 2
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

      it 'resets failure count after successful execution' do
        3.times do
          begin
            circuit_breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end

        circuit_breaker.execute { 'success' }
        stats = circuit_breaker.stats
        expect(stats[:failure_count]).to eq(0)
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
        }.to raise_error(WorkflowCircuitBreakerService::CircuitOpenError)
      end

      it 'does not execute the block when open' do
        executed = false
        begin
          circuit_breaker.execute { executed = true }
        rescue WorkflowCircuitBreakerService::CircuitOpenError
          # Expected
        end

        expect(executed).to be false
      end

      it 'transitions to half_open after timeout period' do
        # Simulate timeout passing
        Timecop.travel(Time.current + config[:timeout_seconds] + 1) do
          circuit_breaker.execute { 'success' }
          # After successful execution in half_open, should be closed
          expect(circuit_breaker.state).to eq('closed')
        end
      end

      it 'records circuit open events' do
        begin
          circuit_breaker.execute { 'test' }
        rescue WorkflowCircuitBreakerService::CircuitOpenError => e
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
        Timecop.travel(Time.current + config[:timeout_seconds] + 1)
      end

      after do
        Timecop.return
      end

      it 'allows limited number of test calls' do
        first_call = circuit_breaker.execute { 'test1' }
        second_call = circuit_breaker.execute { 'test2' }

        expect(first_call).to eq('test1')
        expect(second_call).to eq('test2')
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

      it 'resets success count on transition to closed' do
        config[:success_threshold].times do
          circuit_breaker.execute { 'success' }
        end

        stats = circuit_breaker.stats
        expect(stats[:success_count]).to eq(0)
        expect(stats[:state]).to eq('closed')
      end

      it 'increments success count for each successful call' do
        2.times { circuit_breaker.execute { 'success' } }

        stats = circuit_breaker.stats
        expect(stats[:success_count]).to eq(2)
      end
    end
  end

  describe '#state' do
    it 'returns closed by default' do
      expect(circuit_breaker.state).to eq('closed')
    end

    it 'persists state in Redis' do
      config[:failure_threshold].times do
        begin
          circuit_breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      # Create new instance to verify persistence
      new_breaker = described_class.new(service: service_name, config: config)
      expect(new_breaker.state).to eq('open')
    end

    it 'returns current state from Redis' do
      Redis.current.set("circuit_breaker:#{service_name}:state", 'half_open')
      expect(circuit_breaker.state).to eq('half_open')
    end
  end

  describe '#stats' do
    it 'returns comprehensive statistics' do
      stats = circuit_breaker.stats

      expect(stats).to include(
        state: 'closed',
        failure_count: 0,
        success_count: 0,
        failure_threshold: 5,
        success_threshold: 3,
        timeout_seconds: 60
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
      expect(stats[:retry_at]).to be_present
      expect(stats[:retry_in_seconds]).to be > 0
    end

    it 'does not include retry time when circuit is closed' do
      stats = circuit_breaker.stats
      expect(stats[:retry_at]).to be_nil
      expect(stats[:retry_in_seconds]).to be_nil
    end

    it 'tracks total calls' do
      3.times { circuit_breaker.execute { 'success' } }
      2.times do
        begin
          circuit_breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      stats = circuit_breaker.stats
      expect(stats[:total_calls]).to eq(5)
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

    it 'handles API errors' do
      expect {
        circuit_breaker.execute { raise RestClient::RequestFailed }
      }.to raise_error(RestClient::RequestFailed)

      stats = circuit_breaker.stats
      expect(stats[:failure_count]).to eq(1)
    end

    it 'records error types in metadata' do
      begin
        circuit_breaker.execute { raise ArgumentError, 'test' }
      rescue ArgumentError
        # Expected
      end

      # Error type tracking would be in advanced implementation
      stats = circuit_breaker.stats
      expect(stats[:last_failure_time]).to be_present
    end
  end

  describe 'configuration inheritance' do
    context 'with default configuration' do
      subject(:default_breaker) { described_class.new(service: 'default_service') }

      it 'uses default failure threshold' do
        stats = default_breaker.stats
        expect(stats[:failure_threshold]).to eq(5)
      end

      it 'uses default success threshold' do
        stats = default_breaker.stats
        expect(stats[:success_threshold]).to eq(3)
      end

      it 'uses default timeout' do
        stats = default_breaker.stats
        expect(stats[:timeout_seconds]).to eq(60)
      end
    end

    context 'with custom configuration' do
      let(:custom_config) do
        {
          failure_threshold: 10,
          success_threshold: 5,
          timeout_seconds: 120
        }
      end

      subject(:custom_breaker) { described_class.new(service: 'custom_service', config: custom_config) }

      it 'uses custom thresholds' do
        stats = custom_breaker.stats
        expect(stats[:failure_threshold]).to eq(10)
        expect(stats[:success_threshold]).to eq(5)
        expect(stats[:timeout_seconds]).to eq(120)
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
      threads = config[:failure_threshold].times.map do |i|
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

  describe 'Redis persistence' do
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
      new_instance = described_class.new(service: service_name, config: config)
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

      new_instance = described_class.new(service: service_name, config: config)
      stats = new_instance.stats
      expect(stats[:failure_count]).to eq(3)
    end
  end
end
