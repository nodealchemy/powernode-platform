# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkflowCircuitBreakerManager do
  let(:account) { create(:account) }

  before do
    # Clear all circuit breaker state
    Redis.current.keys('circuit_breaker:*').each do |key|
      Redis.current.del(key)
    end
  end

  describe '.get_breaker' do
    it 'returns circuit breaker for service' do
      breaker = described_class.get_breaker('test_service')
      expect(breaker).to be_a(AiWorkflowCircuitBreakerService)
    end

    it 'returns same instance for same service' do
      breaker1 = described_class.get_breaker('test_service')
      breaker2 = described_class.get_breaker('test_service')
      expect(breaker1.object_id).to eq(breaker2.object_id)
    end

    it 'returns different instances for different services' do
      breaker1 = described_class.get_breaker('service_a')
      breaker2 = described_class.get_breaker('service_b')
      expect(breaker1.object_id).not_to eq(breaker2.object_id)
    end

    it 'applies custom configuration when provided' do
      config = { failure_threshold: 10, timeout_seconds: 120 }
      breaker = described_class.get_breaker('custom_service', config: config)

      stats = breaker.stats
      expect(stats[:failure_threshold]).to eq(10)
      expect(stats[:timeout_seconds]).to eq(120)
    end

    it 'uses default configuration when none provided' do
      breaker = described_class.get_breaker('default_service')

      stats = breaker.stats
      expect(stats[:failure_threshold]).to eq(5)
      expect(stats[:success_threshold]).to eq(3)
      expect(stats[:timeout_seconds]).to eq(60)
    end
  end

  describe '.execute_with_breaker' do
    it 'executes block through circuit breaker' do
      result = described_class.execute_with_breaker('test_service') { 'success' }
      expect(result).to eq('success')
    end

    it 'records success in circuit breaker' do
      described_class.execute_with_breaker('test_service') { 'success' }

      breaker = described_class.get_breaker('test_service')
      stats = breaker.stats
      expect(stats[:success_count]).to eq(1)
    end

    it 'records failure in circuit breaker' do
      expect {
        described_class.execute_with_breaker('test_service') { raise StandardError }
      }.to raise_error(StandardError)

      breaker = described_class.get_breaker('test_service')
      stats = breaker.stats
      expect(stats[:failure_count]).to eq(1)
    end

    it 'raises CircuitOpenError when circuit is open' do
      # Trip the circuit
      5.times do
        begin
          described_class.execute_with_breaker('test_service') { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      expect {
        described_class.execute_with_breaker('test_service') { 'should not execute' }
      }.to raise_error(AiWorkflowCircuitBreakerService::CircuitOpenError)
    end
  end

  describe '.all_services' do
    it 'returns all registered circuit breakers' do
      described_class.get_breaker('service_a')
      described_class.get_breaker('service_b')
      described_class.get_breaker('service_c')

      services = described_class.all_services
      expect(services).to contain_exactly('service_a', 'service_b', 'service_c')
    end

    it 'returns empty array when no services registered' do
      services = described_class.all_services
      expect(services).to eq([])
    end
  end

  describe '.health_check' do
    before do
      described_class.get_breaker('healthy_service')

      # Create unhealthy service
      unhealthy = described_class.get_breaker('unhealthy_service')
      5.times do
        begin
          unhealthy.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      # Create degraded service
      degraded = described_class.get_breaker('degraded_service')
      5.times do
        begin
          degraded.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      # Move to half_open
      Timecop.travel(Time.current + 61) do
        begin
          degraded.execute { 'test' }
        rescue
          # May fail or succeed
        end
      end
    end

    it 'returns health status for all services' do
      health = described_class.health_check

      expect(health).to be_a(Hash)
      expect(health.keys).to include('healthy_service', 'unhealthy_service', 'degraded_service')
    end

    it 'identifies healthy services' do
      health = described_class.health_check
      expect(health['healthy_service'][:state]).to eq('closed')
      expect(health['healthy_service'][:healthy]).to be true
    end

    it 'identifies unhealthy services' do
      health = described_class.health_check
      expect(health['unhealthy_service'][:state]).to eq('open')
      expect(health['unhealthy_service'][:healthy]).to be false
    end

    it 'includes failure statistics' do
      health = described_class.health_check

      health.each do |service, data|
        expect(data).to include(:state, :failure_count, :healthy)
      end
    end

    it 'includes retry information for open circuits' do
      health = described_class.health_check
      unhealthy_data = health['unhealthy_service']

      expect(unhealthy_data[:retry_at]).to be_present
      expect(unhealthy_data[:retry_in_seconds]).to be > 0
    end
  end

  describe '.reset_all!' do
    before do
      # Create and trip multiple circuits
      %w[service_a service_b service_c].each do |service|
        breaker = described_class.get_breaker(service)
        5.times do
          begin
            breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end
      end
    end

    it 'resets all circuit breakers' do
      described_class.reset_all!

      %w[service_a service_b service_c].each do |service|
        breaker = described_class.get_breaker(service)
        expect(breaker.state).to eq('closed')
      end
    end

    it 'clears failure counts for all services' do
      described_class.reset_all!

      health = described_class.health_check
      health.each do |service, data|
        expect(data[:failure_count]).to eq(0)
      end
    end

    it 'returns count of reset services' do
      count = described_class.reset_all!
      expect(count).to eq(3)
    end
  end

  describe '.reset_service' do
    before do
      breaker = described_class.get_breaker('test_service')
      5.times do
        begin
          breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end
    end

    it 'resets specific service circuit breaker' do
      described_class.reset_service('test_service')

      breaker = described_class.get_breaker('test_service')
      expect(breaker.state).to eq('closed')
    end

    it 'returns true when service exists' do
      result = described_class.reset_service('test_service')
      expect(result).to be true
    end

    it 'returns false when service does not exist' do
      result = described_class.reset_service('nonexistent_service')
      expect(result).to be false
    end

    it 'does not affect other services' do
      other_breaker = described_class.get_breaker('other_service')
      5.times do
        begin
          other_breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      described_class.reset_service('test_service')

      expect(other_breaker.state).to eq('open')
    end
  end

  describe '.get_stats' do
    before do
      described_class.get_breaker('service_a').execute { 'success' }

      5.times do
        begin
          described_class.get_breaker('service_b').execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end
    end

    it 'returns statistics for specific service' do
      stats = described_class.get_stats('service_a')

      expect(stats).to include(
        state: 'closed',
        success_count: 1,
        failure_count: 0
      )
    end

    it 'includes comprehensive metrics' do
      stats = described_class.get_stats('service_b')

      expect(stats).to include(
        :state,
        :failure_count,
        :success_count,
        :failure_threshold,
        :timeout_seconds,
        :last_failure_time
      )
    end

    it 'returns nil for nonexistent service' do
      stats = described_class.get_stats('nonexistent')
      expect(stats).to be_nil
    end
  end

  describe '.unhealthy_services' do
    before do
      described_class.get_breaker('healthy')

      %w[unhealthy_a unhealthy_b].each do |service|
        breaker = described_class.get_breaker(service)
        5.times do
          begin
            breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end
      end
    end

    it 'returns list of unhealthy service names' do
      unhealthy = described_class.unhealthy_services
      expect(unhealthy).to contain_exactly('unhealthy_a', 'unhealthy_b')
    end

    it 'does not include healthy services' do
      unhealthy = described_class.unhealthy_services
      expect(unhealthy).not_to include('healthy')
    end

    it 'returns empty array when all services healthy' do
      described_class.reset_all!
      unhealthy = described_class.unhealthy_services
      expect(unhealthy).to eq([])
    end
  end

  describe '.degraded_services' do
    before do
      # Create half-open circuit
      breaker = described_class.get_breaker('degraded')
      5.times do
        begin
          breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      # Transition to half_open
      Timecop.travel(Time.current + 61) do
        Redis.current.set("circuit_breaker:degraded:state", 'half_open')
      end
    end

    it 'returns list of degraded service names' do
      degraded = described_class.degraded_services
      expect(degraded).to include('degraded')
    end

    it 'does not include closed or open circuits' do
      described_class.get_breaker('healthy')

      unhealthy = described_class.get_breaker('unhealthy')
      5.times do
        begin
          unhealthy.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      degraded = described_class.degraded_services
      expect(degraded).not_to include('healthy', 'unhealthy')
    end
  end

  describe 'service-specific configurations' do
    it 'applies AI provider configuration' do
      breaker = described_class.get_breaker('ai_provider_anthropic', config: {
        failure_threshold: 3,
        timeout_seconds: 30
      })

      stats = breaker.stats
      expect(stats[:failure_threshold]).to eq(3)
      expect(stats[:timeout_seconds]).to eq(30)
    end

    it 'applies webhook configuration' do
      breaker = described_class.get_breaker('webhook_delivery', config: {
        failure_threshold: 10,
        timeout_seconds: 120
      })

      stats = breaker.stats
      expect(stats[:failure_threshold]).to eq(10)
      expect(stats[:timeout_seconds]).to eq(120)
    end

    it 'applies external API configuration' do
      breaker = described_class.get_breaker('external_api', config: {
        failure_threshold: 5,
        success_threshold: 2,
        timeout_seconds: 60
      })

      stats = breaker.stats
      expect(stats[:success_threshold]).to eq(2)
    end
  end

  describe 'monitoring and alerts' do
    it 'detects when circuit breaker opens' do
      breaker = described_class.get_breaker('monitored_service')

      initial_state = breaker.state

      5.times do
        begin
          breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      expect(initial_state).to eq('closed')
      expect(breaker.state).to eq('open')
    end

    it 'tracks state transitions' do
      breaker = described_class.get_breaker('transition_test')

      states = []
      states << breaker.state  # closed

      5.times do
        begin
          breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end
      states << breaker.state  # open

      Timecop.travel(Time.current + 61) do
        begin
          breaker.execute { 'test' }
        rescue
          # May succeed or fail
        end
        states << breaker.state  # half_open or closed
      end

      expect(states[0]).to eq('closed')
      expect(states[1]).to eq('open')
      expect(states[2]).to be_in(['half_open', 'closed'])
    end
  end

  describe 'WebSocket integration' do
    it 'broadcasts state changes via WebSocket' do
      # This would test WebSocket broadcast when implemented
      expect(ActionCable.server).to receive(:broadcast).at_least(:once)

      breaker = described_class.get_breaker('websocket_test')
      5.times do
        begin
          breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end
    end
  end

  describe 'concurrent operations' do
    it 'handles concurrent service registrations' do
      threads = 10.times.map do |i|
        Thread.new do
          described_class.get_breaker("concurrent_service_#{i}")
        end
      end

      threads.each(&:join)

      services = described_class.all_services
      expect(services.length).to eq(10)
    end

    it 'maintains consistent state across threads' do
      breaker = described_class.get_breaker('thread_safe')

      threads = 5.times.map do
        Thread.new do
          begin
            breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end
      end

      threads.each(&:join)
      expect(breaker.state).to eq('open')
    end
  end
end
