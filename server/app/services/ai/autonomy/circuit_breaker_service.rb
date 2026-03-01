# frozen_string_literal: true

module Ai
  module Autonomy
    class CircuitBreakerService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Check if an action is allowed by the circuit breaker
      # @param agent [Ai::Agent] The agent
      # @param action_type [String] The action type
      # @return [Hash] { allowed: Boolean, state: String, reason: String|nil }
      def check(agent:, action_type:)
        breaker = find_or_create(agent, action_type)

        # If open and cooldown expired, transition to half_open
        breaker.attempt_reset! if breaker.open?

        case breaker.state
        when "closed"
          { allowed: true, state: "closed", reason: nil }
        when "open"
          { allowed: false, state: "open", reason: "Circuit breaker open for '#{action_type}' (#{breaker.failure_count} failures)" }
        when "half_open"
          { allowed: true, state: "half_open", reason: "Circuit breaker half-open, testing recovery" }
        end
      end

      # Record a successful action
      # @param agent [Ai::Agent] The agent
      # @param action_type [String] The action type
      def record_success(agent:, action_type:)
        breaker = find_or_create(agent, action_type)
        breaker.update!(
          success_count: breaker.success_count + 1,
          last_success_at: Time.current
        )

        # If half_open and success threshold reached, close
        if breaker.half_open? && breaker.success_count >= breaker.success_threshold
          breaker.close!(reason: "success_threshold_reached_after_recovery")
        end

        breaker
      end

      # Record a failed action
      # @param agent [Ai::Agent] The agent
      # @param action_type [String] The action type
      def record_failure(agent:, action_type:)
        breaker = find_or_create(agent, action_type)
        breaker.update!(
          failure_count: breaker.failure_count + 1,
          last_failure_at: Time.current
        )

        # If half_open, any failure trips immediately
        if breaker.half_open?
          breaker.trip!(reason: "failure_during_half_open")
          return breaker
        end

        # If closed and failure threshold reached, trip
        if breaker.closed? && breaker.failure_count >= breaker.failure_threshold
          breaker.trip!(reason: "failure_threshold_exceeded")
        end

        breaker
      end

      # Reset a circuit breaker manually
      # @param breaker [Ai::CircuitBreaker] The breaker to reset
      def reset!(breaker)
        breaker.close!(reason: "manual_reset")
        breaker
      end

      # List all circuit breakers for the account
      def list
        Ai::CircuitBreaker.where(account_id: account.id).includes(:agent).order(updated_at: :desc)
      end

      # List circuit breakers for a specific agent
      def for_agent(agent)
        Ai::CircuitBreaker.for_agent(agent.id).where(account_id: account.id)
      end

      private

      def find_or_create(agent, action_type)
        Ai::CircuitBreaker.find_or_create_by!(agent_id: agent.id, action_type: action_type.to_s) do |cb|
          cb.account = account
        end
      end
    end
  end
end
