# frozen_string_literal: true

# Ai::ProviderCircuitBreakerService - Provider-specific circuit breaker
#
# Provides circuit breaker protection specifically for AI providers.
# Uses the shared CircuitBreakerCore concern for core functionality,
# with Redis-based storage for provider state.
#
# Example:
#   provider = Ai::Provider.find(id)
#   breaker = Ai::ProviderCircuitBreakerService.new(provider)
#   breaker.call { provider.execute_request(prompt) }
#
class Ai::ProviderCircuitBreakerService
  include ActiveModel::Model
  include ActiveModel::Attributes
  include CircuitBreakerCore

  # Provider-specific error classes
  class CircuitBreakerOpenError < CircuitBreakerCore::CircuitOpenError; end
  class ProviderUnavailableError < StandardError; end

  attr_reader :provider

  def initialize(provider)
    @provider = provider

    # Setup circuit breaker with provider-specific configuration and Redis storage
    setup_circuit_breaker(
      resource_id: "provider:#{provider.id}",
      service_name: provider.name,
      config: {
        failure_threshold: 5,
        success_threshold: 2,
        timeout_duration: 60_000, # 60 seconds in ms
        storage: :redis
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

  def on_state_change(old_state, new_state)
    if new_state == "open"
      account = @provider.respond_to?(:account) ? @provider.account : nil
      if account
        Ai::SelfHealing::RemediationDispatcher.dispatch(
          account: account,
          trigger_source: "ProviderCircuitBreaker:#{@provider.name}",
          trigger_event: "circuit_breaker_opened",
          context: {
            provider_id: @provider.id,
            service_type: "provider",
            circuit_state: new_state,
            previous_state: old_state,
            failure_count: @consecutive_failures
          }
        )
      end
    end
  rescue => e
    Rails.logger.error "[ProviderCircuitBreaker] Remediation dispatch failed: #{e.message}"
  end

  # Override to use provider ID in the key
  def build_state_key(resource_id)
    "circuit_breaker:#{@provider.id}"
  end
end
