# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Mcp
        # Worker-invoked MCP OAuth housekeeping. Prunes stale MCP sessions, revoked
        # Doorkeeper tokens/grants past retention, and orphaned Dynamic-Client-
        # Registration apps. Authenticated as the worker via mTLS (InternalBaseController).
        class HousekeepingController < Api::V1::Internal::InternalBaseController
          # POST /api/v1/internal/mcp/housekeeping
          def create
            summary = ::Mcp::HousekeepingService.call
            render_success(summary)
          rescue StandardError => e
            Rails.logger.error "[Internal::Mcp::Housekeeping] #{e.class}: #{e.message}"
            render_error("MCP housekeeping failed", status: :internal_server_error)
          end
        end
      end
    end
  end
end
