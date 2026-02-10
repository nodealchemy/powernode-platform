# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::CircuitBreakerRegistry do
  before do
    described_class.clear!
  end

  describe '.get_or_create_breaker' do
    it 'creates a circuit breaker for the service' do
      breaker = described_class.get_or_create_breaker('test_service')
      expect(breaker.circuit_state).to eq('closed')
    end

    it 'returns same instance for same service' do
      breaker1 = described_class.get_or_create_breaker('test_service')
      breaker2 = described_class.get_or_create_breaker('test_service')
      expect(breaker1.object_id).to eq(breaker2.object_id)
    end

    it 'returns different instances for different services' do
      breaker1 = described_class.get_or_create_breaker('service_a')
      breaker2 = described_class.get_or_create_breaker('service_b')
      expect(breaker1.object_id).not_to eq(breaker2.object_id)
    end

    it 'applies custom configuration when provided' do
      config = { failure_threshold: 10, timeout_duration: 120_000 }
      breaker = described_class.get_or_create_breaker('custom_service', config)

      stats = breaker.circuit_stats
      expect(stats[:config][:failure_threshold]).to eq(10)
      expect(stats[:config][:timeout_duration]).to eq(120_000)
    end

    it 'uses default configuration when none provided' do
      breaker = described_class.get_or_create_breaker('default_service')

      stats = breaker.circuit_stats
      expect(stats[:config][:failure_threshold]).to eq(5)
      expect(stats[:config][:success_threshold]).to eq(2)
      expect(stats[:config][:timeout_duration]).to eq(60_000)
    end
  end

  describe '.get_breaker' do
    it 'returns nil for unregistered service' do
      expect(described_class.get_breaker('unknown')).to be_nil
    end

    it 'returns breaker for registered service' do
      described_class.get_or_create_breaker('test_service')
      expect(described_class.get_breaker('test_service')).not_to be_nil
    end
  end

  describe '.protect' do
    it 'executes block with circuit breaker protection' do
      result = described_class.protect(service_name: 'protected_service') { 'result' }
      expect(result).to eq('result')
    end

    it 'records success in circuit breaker' do
      service_name = "success_test_#{SecureRandom.hex(4)}"
      described_class.protect(service_name: service_name) { 'success' }

      breaker = described_class.get_breaker(service_name)
      stats = breaker.circuit_stats
      expect(stats[:success_count]).to be >= 1
    end

    it 'records failure in circuit breaker' do
      expect {
        described_class.protect(service_name: 'test_service') { raise StandardError }
      }.to raise_error(StandardError)

      breaker = described_class.get_breaker('test_service')
      stats = breaker.circuit_stats
      expect(stats[:failure_count]).to eq(1)
    end

    it 'raises CircuitOpenError when circuit is open' do
      5.times do
        begin
          described_class.protect(service_name: 'test_service') { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      expect {
        described_class.protect(service_name: 'test_service') { 'should not execute' }
      }.to raise_error(CircuitBreakerCore::CircuitOpenError)
    end

    it 'accepts custom configuration' do
      described_class.protect(
        service_name: 'custom_config_service',
        config: { failure_threshold: 10 }
      ) { 'result' }

      breaker = described_class.get_breaker('custom_config_service')
      expect(breaker.circuit_stats[:config][:failure_threshold]).to eq(10)
    end
  end

  # Alias test
  describe '.execute_with_breaker' do
    it 'delegates to protect' do
      result = described_class.execute_with_breaker('exec_test_service') { 'success' }
      expect(result).to eq('success')
    end
  end

  describe '.service_available?' do
    it 'returns true for healthy service' do
      described_class.get_or_create_breaker('healthy_service')
      expect(described_class.service_available?('healthy_service')).to be true
    end

    it 'returns false for open circuit' do
      breaker = described_class.get_or_create_breaker('unhealthy_service')
      5.times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
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

  describe '.all_stats' do
    it 'returns all registered circuit breaker stats' do
      described_class.get_or_create_breaker('service_a')
      described_class.get_or_create_breaker('service_b')
      described_class.get_or_create_breaker('service_c')

      stats = described_class.all_stats
      service_names = stats.map { |s| s[:service_name] }
      expect(service_names).to contain_exactly('service_a', 'service_b', 'service_c')
    end

    it 'returns empty array when no services registered' do
      stats = described_class.all_stats
      expect(stats).to eq([])
    end
  end

  describe '.health_check' do
    before do
      described_class.get_or_create_breaker('healthy_service')

      unhealthy = described_class.get_or_create_breaker('unhealthy_service')
      5.times do
        begin
          unhealthy.execute_with_circuit_breaker { raise StandardError }
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
      described_class.get_or_create_breaker('healthy_service')

      unhealthy = described_class.get_or_create_breaker('unhealthy_service')
      5.times do
        begin
          unhealthy.execute_with_circuit_breaker { raise StandardError }
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
      %w[service_a service_b service_c].each do |service|
        breaker = described_class.get_or_create_breaker(service)
        5.times do
          begin
            breaker.execute_with_circuit_breaker { raise StandardError }
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
        expect(breaker.circuit_state).to eq('closed')
      end
    end

    it 'clears failure counts for all services' do
      described_class.reset_all!

      described_class.all_stats.each do |state|
        expect(state[:failure_count]).to eq(0)
      end
    end
  end

  describe '.reset_service!' do
    before do
      breaker = described_class.get_or_create_breaker('test_service')
      5.times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end
    end

    it 'resets specific service circuit breaker' do
      described_class.reset_service!('test_service')

      breaker = described_class.get_breaker('test_service')
      expect(breaker.circuit_state).to eq('closed')
    end

    it 'returns true when service exists' do
      result = described_class.reset_service!('test_service')
      expect(result).to be true
    end

    it 'returns false when service does not exist' do
      result = described_class.reset_service!('nonexistent')
      expect(result).to be false
    end

    it 'does not affect other services' do
      other_breaker = described_class.get_or_create_breaker('other_service')
      5.times do
        begin
          other_breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      described_class.reset_service!('test_service')
      expect(other_breaker.circuit_state).to eq('open')
    end
  end

  describe '.unhealthy_services' do
    before do
      described_class.get_or_create_breaker('healthy')

      %w[unhealthy_a unhealthy_b].each do |service|
        breaker = described_class.get_or_create_breaker(service)
        5.times do
          begin
            breaker.execute_with_circuit_breaker { raise StandardError }
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
      described_class.clear!
      described_class.get_or_create_breaker('healthy_only')

      unhealthy = described_class.unhealthy_services
      expect(unhealthy).to eq([])
    end
  end

  describe '.clear!' do
    it 'removes all cached breakers' do
      described_class.get_or_create_breaker('service_a')
      described_class.get_or_create_breaker('service_b')

      expect(described_class.all_stats.length).to eq(2)

      described_class.clear!

      expect(described_class.all_stats.length).to eq(0)
    end
  end

  describe '.category_stats' do
    it 'returns stats for a specific category' do
      described_class.get_or_create_breaker('openai')
      described_class.get_or_create_breaker('anthropic')

      stats = described_class.category_stats(:ai_providers)
      expect(stats).to be_an(Array)
    end

    it 'returns empty array for unknown category' do
      stats = described_class.category_stats(:unknown_category)
      expect(stats).to eq([])
    end
  end

  describe '.reset_category!' do
    it 'resets circuit breakers in category' do
      breaker = described_class.get_or_create_breaker('openai')
      5.times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      described_class.reset_category!(:ai_providers)
      expect(breaker.circuit_state).to eq('closed')
    end
  end

  describe '.monitor_and_alert' do
    it 'returns health summary' do
      described_class.get_or_create_breaker('monitored_service')

      summary = described_class.monitor_and_alert
      expect(summary).to include(:total_services, :healthy, :unhealthy, :degraded)
    end

    it 'broadcasts alert for unhealthy services' do
      breaker = described_class.get_or_create_breaker('unhealthy_for_alert')
      5.times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      expect(ActionCable.server).to receive(:broadcast).at_least(:once)
      described_class.monitor_and_alert
    end
  end

  describe 'WebSocket integration' do
    it 'broadcasts state changes via WebSocket' do
      expect(ActionCable.server).to receive(:broadcast).at_least(:once)

      breaker = described_class.get_or_create_breaker('websocket_test')
      5.times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
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
          described_class.get_or_create_breaker("concurrent_service_#{i}")
        end
      end

      threads.each(&:join)

      stats = described_class.all_stats
      expect(stats.length).to eq(10)
    end

    it 'maintains consistent state across threads' do
      breaker = described_class.get_or_create_breaker('thread_safe')

      threads = 5.times.map do
        Thread.new do
          begin
            breaker.execute_with_circuit_breaker { raise StandardError }
          rescue StandardError
            # Expected
          end
        end
      end

      threads.each(&:join)
      expect(breaker.circuit_state).to eq('open')
    end
  end

  describe 'circuit breaker lifecycle' do
    let(:service_name) { 'lifecycle_test' }
    let(:config) { { failure_threshold: 5, success_threshold: 3, timeout_duration: 60_000 } }

    before do
      Rails.cache.delete("circuit_breaker:#{service_name}")
    end

    it 'starts in closed state' do
      breaker = described_class.get_or_create_breaker(service_name, config)
      expect(breaker.circuit_state).to eq('closed')
    end

    it 'transitions to open after failure threshold' do
      breaker = described_class.get_or_create_breaker(service_name, config)
      config[:failure_threshold].times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      expect(breaker.circuit_state).to eq('open')
    end

    it 'blocks execution when open' do
      breaker = described_class.get_or_create_breaker(service_name, config)
      config[:failure_threshold].times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      expect {
        breaker.execute_with_circuit_breaker { 'should not execute' }
      }.to raise_error(CircuitBreakerCore::CircuitOpenError)
    end

    it 'transitions to half_open after timeout' do
      breaker = described_class.get_or_create_breaker(service_name, config)
      config[:failure_threshold].times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      timeout_seconds = config[:timeout_duration] / 1000
      travel(timeout_seconds + 1) do
        breaker.execute_with_circuit_breaker { 'success' }
        expect(breaker.circuit_state).to eq('half_open')
      end
    end

    it 'transitions to closed after success threshold in half_open' do
      breaker = described_class.get_or_create_breaker(service_name, config)
      config[:failure_threshold].times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      timeout_seconds = config[:timeout_duration] / 1000
      travel(timeout_seconds + 1) do
        config[:success_threshold].times do
          breaker.execute_with_circuit_breaker { 'success' }
        end
        expect(breaker.circuit_state).to eq('closed')
      end
    end

    it 'supports force open and close' do
      breaker = described_class.get_or_create_breaker(service_name)
      breaker.force_open!
      expect(breaker.circuit_state).to eq('open')

      breaker.force_close!
      expect(breaker.circuit_state).to eq('closed')
    end

    it 'resets consecutive failures after success' do
      breaker = described_class.get_or_create_breaker(service_name, config)
      3.times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end

      breaker.execute_with_circuit_breaker { 'success' }
      stats = breaker.circuit_stats
      expect(stats[:consecutive_failures]).to eq(0)
    end
  end
end
