# frozen_string_literal: true

# Ai::WorkflowCircuitBreakerService - Circuit breaker for AI workflow services
#
# Provides circuit breaker protection for workflow execution services
# including AI providers, external APIs, and internal services.
# Uses the shared CircuitBreakerCore concern for core functionality.
#
# Example:
#   breaker = Ai::WorkflowCircuitBreakerService.new(service_name: 'openai')
#   breaker.execute { call_openai_api }
#
class Ai::WorkflowCircuitBreakerService
  include CircuitBreakerCore

  # Re-export error class for backward compatibility
  CircuitOpenError = CircuitBreakerCore::CircuitOpenError

  def initialize(service_name:, config: {})
    setup_circuit_breaker(
      resource_id: service_name,
      service_name: service_name,
      config: config
    )
  end

  # Execute a block with circuit breaker protection
  # Delegates to CircuitBreakerCore#execute_with_circuit_breaker
  def execute(&block)
    execute_with_circuit_breaker(&block)
  end

  # Get current circuit breaker state
  # Delegates to CircuitBreakerCore#circuit_state
  def state
    circuit_state
  end

  # Get circuit breaker statistics
  # Delegates to CircuitBreakerCore#circuit_stats
  def stats
    circuit_stats
  end

  # Reset circuit breaker to closed state
  # Delegates to CircuitBreakerCore#reset_circuit!
  def reset!
    reset_circuit!
  end

  # Force open the circuit (for maintenance)
  # Delegates to CircuitBreakerCore#force_open!
  def open!
    force_open!
  end

  # Force close the circuit (after manual verification)
  # Delegates to CircuitBreakerCore#force_close!
  def close!
    force_close!
  end

  # Class method to get all circuit breaker states
  def self.all_states
    pattern = "circuit_breaker:*"
    keys = Rails.cache.redis.keys(pattern)

    keys.map do |key|
      service_name = key.sub("circuit_breaker:", "")
      breaker = new(service_name: service_name)
      breaker.stats
    end
  rescue StandardError => e
    Rails.logger.error "[CircuitBreaker] Failed to get all states: #{e.message}"
    []
  end

  private

  # Hook called when circuit state changes
  # Broadcasts state changes via WebSocket
  def on_state_change(old_state, new_state)
    broadcast_state_change(old_state, new_state)
  end

  # Broadcast state change via WebSocket
  def broadcast_state_change(old_state, new_state)
    ActionCable.server.broadcast(
      "ai_monitoring_channel",
      {
        type: "circuit_breaker_state_change",
        service: service_name,
        old_state: old_state,
        new_state: new_state,
        timestamp: Time.current.iso8601,
        stats: stats
      }
    )
  rescue StandardError => e
    Rails.logger.error "[CircuitBreaker] Failed to broadcast state change: #{e.message}"
  end
end
