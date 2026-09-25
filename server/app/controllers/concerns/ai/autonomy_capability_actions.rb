# frozen_string_literal: true

module Ai
  module AutonomyCapabilityActions
    extend ActiveSupport::Concern

    # GET /api/v1/ai/autonomy/capability_matrix
    def capability_matrix
      service = ::Ai::Autonomy::CapabilityMatrixService.new(account: current_account)
      render_success(data: service.full_matrix)
    end
  end
end
