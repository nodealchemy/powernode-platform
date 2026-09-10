# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # PER-AGENT CIRCUIT BREAKERS (`Ai::CircuitBreaker`) as components.
      #
      # One row per (agent, action_type). Kill-switch layer 5 opens every one of
      # them for an account and closes them again on resume
      # (`Ai::Autonomy::KillSwitchService`), so this kind is how an operator sees
      # that a halt actually reached the breakers — and how they see a breaker
      # that failed to close on resume, which the kill switch only logs.
      #
      # ── SCOPE ───────────────────────────────────────────────────────────────
      # `Ai::CircuitBreaker.where(account:)` joined to a non-archived agent.
      # `Ai::Agent` uses `archived` as its retirement state and a breaker
      # outlives the agent's retirement, so an archived agent's breakers are
      # excluded: they are permanently un-actionable, and a tripped breaker on a
      # retired agent would be a red row nobody can ever clear. Agents that are
      # merely `inactive`, `paused` or `error` ARE enumerated — those are
      # operational states, not retirement.
      #
      # ── WHY `open` IS `degraded`, NOT `down` ────────────────────────────────
      # The brief allows `down` if the model distinguishes a hard trip. It does
      # not: `state` is exactly `closed | open | half_open`, `open` always
      # carries a cooldown, and `#attempt_reset!` moves it on by itself. An open
      # breaker is one action type on one agent refusing calls for a bounded
      # time, with the rest of the agent working — degraded, by definition.
      # `down` would put a permanent red on a self-clearing state.
      #
      # ── NOT CONSOLIDATED ────────────────────────────────────────────────────
      # `Ai::CircuitBreaker`, `Monitoring::CircuitBreaker` and the Redis-backed
      # `CircuitBreakerCore` all survive (design decision 7). This contributor
      # reads one of them and deletes nothing.
      class AgentCircuitBreaker < Contributor
        include EnumConditions

        KIND = "agent_circuit_breaker"

        CLOSED_TYPE = "Closed"

        # `Ai::Agent`'s retirement state. See SCOPE.
        EXCLUDED_AGENT_STATUSES = %w[archived].freeze

        # `Ai::CircuitBreaker::STATES`, in full.
        STATE_CONDITIONS = {
          "closed" => {
            type: CLOSED_TYPE, status: true, reason: "BreakerClosed",
            message: "circuit breaker is closed and calls are flowing"
          },
          "open" => {
            type: CLOSED_TYPE, status: false, severity: Condition::SEVERITY_DEGRADED,
            reason: "BreakerOpen",
            message: "circuit breaker is open and is refusing calls"
          },
          "half_open" => {
            type: Condition::PROGRESSING_TYPE, status: true, reason: "BreakerHalfOpen",
            message: "circuit breaker is half-open and probing for recovery"
          }
        }.freeze

        def kind = KIND

        def each_component(account)
          return if account.blank?

          ::Ai::CircuitBreaker
            .where(account_id: account.id)
            .joins(:agent)
            .where.not(ai_agents: { status: EXCLUDED_AGENT_STATUSES })
            .includes(:agent)
            .find_each { |breaker| yield breaker }
        end

        def ref_for(breaker) = breaker.id.to_s

        def display_name_for(breaker)
          "#{breaker.agent&.name.presence || breaker.agent_id} · #{breaker.action_type}"
        end

        def links_for(breaker)
          [ { "label" => "Agent", "path" => "/app/ai/agents/#{breaker.agent_id}" } ]
        end

        def presentation
          { "icon" => "CircuitBoard", "label" => "Agent Circuit Breaker", "group_order" => 40 }
        end

        def conditions_for(breaker)
          [
            enum_condition(
              breaker.state,
              table: STATE_CONDITIONS,
              unknown_type: CLOSED_TYPE,
              evidence: {
                "state" => breaker.state.to_s,
                "action_type" => breaker.action_type,
                "failure_count" => breaker.failure_count,
                "failure_threshold" => breaker.failure_threshold,
                "success_count" => breaker.success_count,
                "success_threshold" => breaker.success_threshold,
                "cooldown_seconds" => breaker.cooldown_seconds,
                "cooldown_expired" => breaker.cooldown_expired?,
                "opened_at" => breaker.opened_at&.iso8601,
                "last_failure_at" => breaker.last_failure_at&.iso8601,
                # WHY the breaker last moved — this is what tells an operator a
                # trip came from the kill switch rather than from real failures.
                "last_transition_reason" => last_transition_reason(breaker)
              }.compact
            )
          ]
        end

        # The agent is not a registered kind in this increment, so declaring an
        # edge to it would point at a component that never exists. `links_for`
        # already takes the operator there.
        def dependencies_for(_breaker) = []

        def actions_for(_breaker) = []

        private

        def last_transition_reason(breaker)
          entry = Array(breaker.history).last
          return nil unless entry.is_a?(Hash)

          (entry["reason"] || entry[:reason])&.to_s
        end
      end
    end
  end
end
