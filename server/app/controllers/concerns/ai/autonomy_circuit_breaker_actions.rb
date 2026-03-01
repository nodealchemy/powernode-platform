# frozen_string_literal: true

module Ai
  module AutonomyCircuitBreakerActions
    extend ActiveSupport::Concern

    # GET /api/v1/ai/autonomy/circuit_breakers
    def circuit_breakers
      service = ::Ai::Autonomy::CircuitBreakerService.new(account: current_account)
      breakers = service.list

      render_success(data: breakers.map { |b| serialize_circuit_breaker(b) })
    end

    # GET /api/v1/ai/autonomy/circuit_breakers/:agent_id
    def agent_circuit_breakers
      agent = current_account.ai_agents.find(params[:agent_id])
      service = ::Ai::Autonomy::CircuitBreakerService.new(account: current_account)
      breakers = service.for_agent(agent)

      render_success(data: breakers.map { |b| serialize_circuit_breaker(b) })
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    end

    # POST /api/v1/ai/autonomy/circuit_breakers/:id/reset
    def reset_circuit_breaker
      breaker = ::Ai::CircuitBreaker.where(account_id: current_account.id).find(params[:id])
      service = ::Ai::Autonomy::CircuitBreakerService.new(account: current_account)
      service.reset!(breaker)

      render_success(data: serialize_circuit_breaker(breaker.reload))
    rescue ActiveRecord::RecordNotFound
      render_not_found("Circuit breaker")
    end

    private

    def serialize_circuit_breaker(breaker)
      {
        id: breaker.id,
        agent_id: breaker.agent_id,
        agent_name: breaker.agent&.name,
        action_type: breaker.action_type,
        state: breaker.state,
        failure_count: breaker.failure_count,
        success_count: breaker.success_count,
        failure_threshold: breaker.failure_threshold,
        success_threshold: breaker.success_threshold,
        cooldown_seconds: breaker.cooldown_seconds,
        last_failure_at: breaker.last_failure_at,
        last_success_at: breaker.last_success_at,
        opened_at: breaker.opened_at,
        half_opened_at: breaker.half_opened_at,
        history: breaker.history || []
      }
    end
  end
end
