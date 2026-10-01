# frozen_string_literal: true

require "shellwords"

module Api
  module V1
    # IMP-2c760325c102 (MCP isolation Phase 1 T4) — the native (unsandboxed)
    # execution hatch's two actions and their serializer, hosted by
    # McpServersController (which declares the routes' before_actions:
    # authenticate_request, require_native_execution_permission and
    # set_mcp_server for both actions). Split out of the controller for
    # size, not reach — nothing here is routable on its own.
    #
    # authz-ok: a controller concern, not a routable controller — it defines
    # actions reached only through McpServersController, whose before_action
    # :require_native_execution_permission gates both.
    module McpServerNativeExecutionActions
      extend ActiveSupport::Concern

      # POST /api/v1/mcp_servers/:id/native_execution
      #
      # Approve this stdio server to run NATIVELY — outside the worker's
      # systemd-run sandbox. Core mode only (McpServer.native_execution_available?);
      # the approval bypasses the sandbox and nothing else (command/args/env
      # validation and package pinning still apply — an unpinned command line
      # is refused here with 422, round 1 item 8), is bound to the current
      # command line (cleared when it changes), is reported to the worker as
      # a computed boolean, and is audited here and again at every native
      # spawn. The audit row records the arg COUNT, never the args.
      def approve_native_execution
        unless McpServer.native_execution_available?
          return render_error("Native execution is only available in core mode (self-hosted, no SaaS layer present)",
                              status: :forbidden)
        end
        unless @mcp_server.connection_type == "stdio"
          return render_error("Native execution applies to stdio MCP servers only", status: :unprocessable_content)
        end

        @mcp_server.approve_native_execution!(current_user)

        render_success({
          mcp_server: serialize_mcp_server(@mcp_server),
          message: "Native execution approved — this server will run outside the sandbox"
        })

        log_audit_event("mcp.servers.native_execution_approve", @mcp_server,
                        severity: "high", risk_level: "high", metadata: audit_command_shape(@mcp_server))
      rescue McpServer::NativeExecutionRefused => e
        render_error("Native execution cannot be approved for this command line: #{e.message}",
                     status: :unprocessable_content)
      rescue StandardError => e
        Rails.logger.error "Failed to approve native execution: #{e.message}"
        render_error("Failed to approve native execution", status: :internal_server_error)
      end

      # DELETE /api/v1/mcp_servers/:id/native_execution
      # Allowed in every mode — withdrawing the hatch is never gated.
      def revoke_native_execution
        @mcp_server.revoke_native_execution!

        render_success({
          mcp_server: serialize_mcp_server(@mcp_server),
          message: "Native execution revoked — this server will run sandboxed"
        })

        log_audit_event("mcp.servers.native_execution_revoke", @mcp_server,
                        severity: "high", risk_level: "high", metadata: { reason: "operator" })
      rescue StandardError => e
        Rails.logger.error "Failed to revoke native execution: #{e.message}"
        render_error("Failed to revoke native execution", status: :internal_server_error)
      end

      private

      def require_native_execution_permission
        unless current_user.has_permission?("mcp.servers.native_execution")
          render_error("Insufficient permissions to approve native execution", status: :forbidden)
        end
      end

      # The token-free description of a command line that the approval
      # audit row carries — the SAME shape and arithmetic as the
      # `mcp.servers.spawn_refused` rows (Mcp::SecurityService's
      # record_spawn_refusal_audit and the worker's SpawnAuditReporter):
      # `launcher` is the program's basename and `arg_count` counts the
      # command string's tokens after the program plus `args`, so an
      # operator reading the two actions side by side sees one number.
      def audit_command_shape(server)
        tokens = begin
          Shellwords.split(server.command.to_s)
        rescue ArgumentError
          server.command.to_s.split(/\s+/)
        end
        { launcher: File.basename(tokens.first.to_s), arg_count: tokens.drop(1).size + Array(server.args).size }
      end

      # The hatch's state, read-only: `available` is the core-mode gate,
      # `approved` the stored approval, `effective` what the worker is told.
      def serialize_native_execution(server)
        {
          available: McpServer.native_execution_available?,
          approved: server.native_execution_approved?,
          effective: server.native_execution_effective?,
          approved_at: server.native_execution_approval&.dig("approved_at"),
          approved_by_id: server.native_execution_approval&.dig("approved_by_id")
        }
      end
    end
  end
end
