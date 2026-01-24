# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::WorkflowCircuitBreakerManager do
  before do
    # Clear circuit breaker state before each test
    described_class.clear_breakers!
  end

  describe '.get_breaker' do
    it 'returns circuit breaker for service' do
      breaker = described_class.get_breaker('test_service')
      expect(breaker).to be_a(Ai::WorkflowCircuitBreakerService)
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
  end

  describe '.get_or_create_breaker' do
    it 'applies custom configuration when provided' do
      config = { failure_threshold: 10, timeout_duration: 120_000 }
      breaker = described_class.get_or_create_breaker('custom_service', config)

      stats = breaker.stats
      expect(stats[:config][:failure_threshold]).to eq(10)
      expect(stats[:config][:timeout_duration]).to eq(120_000)
    end

    it 'uses default configuration when none provided' do
      breaker = described_class.get_or_create_breaker('default_service')

      stats = breaker.stats
      expect(stats[:config][:failure_threshold]).to eq(5)
      expect(stats[:config][:success_threshold]).to eq(2)
      expect(stats[:config][:timeout_duration]).to eq(60_000)
    end
  end

  describe '.execute_with_breaker' do
    it 'executes block through circuit breaker' do
      result = described_class.execute_with_breaker('exec_test_service') { 'success' }
      expect(result).to eq('success')
    end

    it 'records success in circuit breaker' do
      # Use unique service name to avoid cache state from other tests
      service_name = "success_test_#{SecureRandom.hex(4)}"
      described_class.execute_with_breaker(service_name) { 'success' }

      breaker = described_class.get_breaker(service_name)
      stats = breaker.stats
      expect(stats[:success_count]).to be >= 1
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
      }.to raise_error(Ai::WorkflowCircuitBreakerService::CircuitOpenError)
    end
  end

  describe '.all_states' do
    it 'returns all registered circuit breaker states' do
      described_class.get_breaker('service_a')
      described_class.get_breaker('service_b')
      described_class.get_breaker('service_c')

      states = described_class.all_states
      service_names = states.map { |s| s[:service_name] }
      expect(service_names).to contain_exactly('service_a', 'service_b', 'service_c')
    end

    it 'returns empty array when no services registered' do
      states = described_class.all_states
      expect(states).to eq([])
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
    end

    it 'returns health status for all services' do
      health = described_class.health_check

      expect(health).to be_a(Hash)
      expect(health.keys).to include('healthy_service', 'unhealthy_service')
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

      health.each do |_service, data|
        expect(data).to include(:state, :failure_count, :healthy)
      end
    end
  end

  describe '.health_summary' do
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
    end

    it 'returns summary of all circuit breakers' do
      summary = described_class.health_summary

      expect(summary).to include(
        :total_services,
        :healthy,
        :degraded,
        :unhealthy,
        :services_by_state,
        :last_updated
      )
    end

    it 'counts healthy and unhealthy services' do
      summary = described_class.health_summary

      expect(summary[:total_services]).to eq(2)
      expect(summary[:healthy]).to eq(1)
      expect(summary[:unhealthy]).to eq(1)
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

      described_class.all_states.each do |state|
        expect(state[:failure_count]).to eq(0)
      end
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

    it 'creates and resets service if it does not exist' do
      # get_breaker creates the breaker if it doesn't exist, so reset_service returns true
      result = described_class.reset_service('new_service_to_reset')
      # Since get_breaker creates the breaker, it can be reset
      expect(result).to be true
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
      described_class.clear_breakers!
      described_class.get_breaker('healthy_only')

      unhealthy = described_class.unhealthy_services
      expect(unhealthy).to eq([])
    end
  end

  describe '.service_available?' do
    it 'returns true for healthy service' do
      described_class.get_breaker('healthy_service')
      expect(described_class.service_available?('healthy_service')).to be true
    end

    it 'returns false for open circuit' do
      breaker = described_class.get_breaker('unhealthy_service')
      5.times do
        begin
          breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      expect(described_class.service_available?('unhealthy_service')).to be false
    end

    it 'returns true for unregistered service' do
      expect(described_class.service_available?('unknown_service')).to be true
    end
  end

  describe '.protect' do
    it 'executes block with circuit breaker protection' do
      result = described_class.protect(service_name: 'protected_service') { 'result' }
      expect(result).to eq('result')
    end

    it 'accepts custom configuration' do
      described_class.protect(
        service_name: 'custom_config_service',
        config: { failure_threshold: 10 }
      ) { 'result' }

      breaker = described_class.get_breaker('custom_config_service')
      expect(breaker.stats[:config][:failure_threshold]).to eq(10)
    end
  end

  describe '.clear_breakers!' do
    it 'removes all cached breakers' do
      described_class.get_breaker('service_a')
      described_class.get_breaker('service_b')

      expect(described_class.all_states.length).to eq(2)

      described_class.clear_breakers!

      expect(described_class.all_states.length).to eq(0)
    end
  end

  describe 'service-specific configurations' do
    it 'applies AI provider configuration' do
      breaker = described_class.get_or_create_breaker('ai_provider_anthropic', {
        failure_threshold: 3,
        timeout_duration: 30_000
      })

      stats = breaker.stats
      expect(stats[:config][:failure_threshold]).to eq(3)
      expect(stats[:config][:timeout_duration]).to eq(30_000)
    end

    it 'applies webhook configuration' do
      breaker = described_class.get_or_create_breaker('webhook_delivery', {
        failure_threshold: 10,
        timeout_duration: 120_000
      })

      stats = breaker.stats
      expect(stats[:config][:failure_threshold]).to eq(10)
      expect(stats[:config][:timeout_duration]).to eq(120_000)
    end

    it 'applies external API configuration' do
      breaker = described_class.get_or_create_breaker('external_api', {
        failure_threshold: 5,
        success_threshold: 2,
        timeout_duration: 60_000
      })

      stats = breaker.stats
      expect(stats[:config][:success_threshold]).to eq(2)
    end
  end

  describe 'monitoring and alerts' do
    it 'detects when circuit breaker opens' do
      breaker = described_class.get_breaker('monitored_service')
      breaker.reset_circuit!  # Ensure clean state (clear_breakers! only clears in-memory, not cache)

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
      breaker.reset_circuit!  # Ensure clean state (clear_breakers! only clears in-memory, not cache)

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

      expect(states[0]).to eq('closed')
      expect(states[1]).to eq('open')
    end
  end

  describe 'WebSocket integration' do
    it 'broadcasts state changes via WebSocket' do
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

      states = described_class.all_states
      expect(states.length).to eq(10)
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

  describe '.category_states' do
    it 'returns states for a specific category' do
      # Register services in the ai_providers category
      described_class.get_or_create_breaker('openai')
      described_class.get_or_create_breaker('anthropic')

      states = described_class.category_states(:ai_providers)
      expect(states).to be_an(Array)
    end

    it 'returns empty array for unknown category' do
      states = described_class.category_states(:unknown_category)
      expect(states).to eq([])
    end
  end

  describe '.monitor_and_alert' do
    it 'returns health summary' do
      described_class.get_breaker('monitored_service')

      summary = described_class.monitor_and_alert
      expect(summary).to include(:total_services, :healthy, :unhealthy, :degraded)
    end

    it 'broadcasts alert for unhealthy services' do
      breaker = described_class.get_breaker('unhealthy_for_alert')
      5.times do
        begin
          breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      expect(ActionCable.server).to receive(:broadcast).at_least(:once)
      described_class.monitor_and_alert
    end
  end
end
