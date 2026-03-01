# frozen_string_literal: true

module Ai
  module AutonomyShadowActions
    extend ActiveSupport::Concern

    # GET /api/v1/ai/autonomy/shadow_executions
    def shadow_executions
      service = ::Ai::Autonomy::ShadowModeService.new(account: current_account)
      executions = service.list(limit: params[:limit]&.to_i || 50)

      render_success(data: executions.map { |e| serialize_shadow_execution(e) })
    end

    # GET /api/v1/ai/autonomy/shadow_executions/:agent_id
    def agent_shadow_executions
      agent = current_account.ai_agents.find(params[:agent_id])
      service = ::Ai::Autonomy::ShadowModeService.new(account: current_account)
      executions = service.for_agent(agent, limit: params[:limit]&.to_i || 50)

      render_success(data: executions.map { |e| serialize_shadow_execution(e) })
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    end

    private

    def serialize_shadow_execution(execution)
      {
        id: execution.id,
        agent_id: execution.agent_id,
        agent_name: execution.agent&.name,
        action_type: execution.action_type,
        shadow_input: execution.shadow_input,
        shadow_output: execution.shadow_output,
        reference_output: execution.reference_output,
        agreed: execution.agreed,
        agreement_score: execution.agreement_score,
        created_at: execution.created_at
      }
    end
  end
end
