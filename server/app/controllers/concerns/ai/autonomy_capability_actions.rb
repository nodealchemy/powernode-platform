# frozen_string_literal: true

module Ai
  module AutonomyCapabilityActions
    extend ActiveSupport::Concern

    # GET /api/v1/ai/autonomy/capability_matrix
    def capability_matrix
      service = ::Ai::Autonomy::CapabilityMatrixService.new(account: current_account)
      render_success(data: service.full_matrix)
    end

    # GET /api/v1/ai/autonomy/capability_matrix/:agent_id
    def agent_capabilities
      agent = current_account.ai_agents.find(params[:agent_id])
      service = ::Ai::Autonomy::CapabilityMatrixService.new(account: current_account)
      render_success(data: service.agent_capabilities(agent: agent))
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    end
  end
end
