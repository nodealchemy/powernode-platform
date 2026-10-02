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

          # GET /api/v1/internal/mcp/sandbox_cache_policy
          #
          # What the worker's sandbox cache pruner needs from the database: the
          # accounts that still exist and the operator's idle age. See
          # Mcp::SandboxCachePolicy.
          def sandbox_cache_policy
            render_success(::Mcp::SandboxCachePolicy.call)
          end
        end
      end
    end
  end
end
