# frozen_string_literal: true

# AiProviderCircuitBreakerService - Provider-specific circuit breaker
#
# Provides circuit breaker protection specifically for AI providers.
# Uses the shared CircuitBreakerCore concern for core functionality,
# with Redis-based storage for provider state.
#
# Example:
#   provider = Ai::Provider.find(id)
#   breaker = AiProviderCircuitBreakerService.new(provider)
#   breaker.call { provider.execute_request(prompt) }
#
class AiProviderCircuitBreakerService
  include ActiveModel::Model
  include ActiveModel::Attributes
  include CircuitBreakerCore

  # Provider-specific error classes
  class CircuitBreakerOpenError < CircuitBreakerCore::CircuitOpenError; end
  class ProviderUnavailableError < StandardError; end

  attr_reader :provider

  def initialize(provider)
    @provider = provider
    @redis = Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")

    # Setup circuit breaker with provider-specific configuration
    setup_circuit_breaker(
      resource_id: "provider:#{provider.id}",
      service_name: provider.name,
      config: {
        failure_threshold: 5,
        success_threshold: 2,
        timeout_duration: 60_000 # 60 seconds in ms
      }
    )
  end

  # Execute with circuit breaker protection (provider-specific alias)
  # Delegates to CircuitBreakerCore#execute_with_circuit_breaker
  def call(&block)
    execute_with_circuit_breaker(&block)
  rescue CircuitBreakerCore::CircuitOpenError => e
    # Re-raise as provider-specific error for backward compatibility
    raise CircuitBreakerOpenError, e.message
  end

  # Check if provider is available
  # @return [Boolean] true if provider can accept requests
  def provider_available?
    allow_request?
  end

  # Get provider-specific circuit stats
  # Extends base stats with provider information
  def circuit_stats
    super.merge(
      provider_id: @provider.id,
      provider_name: @provider.name,
      can_attempt: provider_available?
    )
  end

  # Check all providers and return their circuit breaker status
  def self.all_provider_stats
    Ai::Provider.active.map do |provider|
      new(provider).circuit_stats
    end
  end

  # Reset all circuit breakers (emergency use)
  def self.reset_all_circuits
    Ai::Provider.active.find_each do |provider|
      new(provider).reset_circuit!
    end
  end

  # Alias for backward compatibility
  def reset_circuit
    reset_circuit!
  end

  # Alias for backward compatibility (returns symbol instead of string)
  def circuit_state
    super.to_sym
  end

  # Get failure count from circuit stats
  def failure_count
    circuit_stats[:failure_count]
  end

  # Get last failure time from circuit stats
  def last_failure_time
    circuit_stats[:last_failure_time]
  end

  # Calculate time until retry is allowed
  def time_until_retry
    next_retry = circuit_stats[:next_retry_at]
    return 0 unless next_retry && super == "open"

    [ (next_retry - Time.current).to_i, 0 ].max
  end

  private

  # Override to use Redis directly instead of Rails.cache
  # This provides better control and isolation for provider state
  def build_state_key(resource_id)
    "circuit_breaker:#{@provider.id}"
  end

  # Override to use Redis directly
  def load_circuit_state
    state_data = @redis.get(state_key)

    if state_data
      cached = JSON.parse(state_data, symbolize_names: true)
      @state = cached[:state] || "closed"
      @failure_count = cached[:failure_count] || 0
      @success_count = cached[:success_count] || 0
      @consecutive_failures = cached[:consecutive_failures] || 0
      @consecutive_successes = cached[:consecutive_successes] || 0
      @last_failure_time = cached[:last_failure_time] ? Time.parse(cached[:last_failure_time]) : nil
      @last_success_time = cached[:last_success_time] ? Time.parse(cached[:last_success_time]) : nil
      @state_changed_at = cached[:state_changed_at] ? Time.parse(cached[:state_changed_at]) : Time.current
    else
      reset_circuit!
    end
  rescue JSON::ParserError, StandardError => e
    Rails.logger.error "[CircuitBreaker:#{@provider.name}] Failed to load state: #{e.message}"
    reset_circuit!
  end

  # Override to use Redis directly
  def save_circuit_state
    state_data = {
      state: @state,
      failure_count: @failure_count,
      success_count: @success_count,
      consecutive_failures: @consecutive_failures,
      consecutive_successes: @consecutive_successes,
      last_failure_time: @last_failure_time&.iso8601,
      last_success_time: @last_success_time&.iso8601,
      state_changed_at: @state_changed_at.iso8601
    }

    @redis.set(state_key, state_data.to_json)
    @redis.expire(state_key, 24.hours.to_i)
  rescue StandardError => e
    Rails.logger.error "[CircuitBreaker:#{@provider.name}] Failed to save state: #{e.message}"
  end
end
