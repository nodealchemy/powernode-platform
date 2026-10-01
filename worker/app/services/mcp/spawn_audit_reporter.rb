# frozen_string_literal: true

require_relative '../backend_api_client'

module Mcp
  # IMP-2c760325c102 (MCP isolation Phase 1 T4) — the worker's audit sink
  # for stdio MCP spawn events, injected into McpSecurityService as its
  # .audit_reporter at boot (config/boot.rb). Two events:
  #
  #   * mcp.servers.spawn_refused — McpSecurityService.validate_stdio_server!
  #     refused the server's command/args/env (an unpinned package, an
  #     inline-code flag, a forbidden env var, ...), on any of the worker's
  #     four stdio paths.
  #   * mcp.servers.native_execution_spawn — the operator-approved native
  #     (unsandboxed) escape hatch was exercised for a spawn.
  #
  # Rows go through the EXISTING internal audit endpoint
  # (POST /api/v1/internal/audit_logs, mTLS, same as every other worker-
  # originated audit row), attributed to the MCP server as the resource.
  # The payload names the server, the command and the error — NEVER
  # `server['env']` (API tokens, credentials) or any env VALUE; the only
  # env-related content is the forbidden KEY names the error message
  # itself already carries.
  #
  # Never raises. An audit failure is logged, not allowed to become a
  # refused (or, worse, an unsandboxed) spawn; the security verdict is
  # decided before this is ever called.
  class SpawnAuditReporter
    ACTION_SPAWN_REFUSED = 'mcp.servers.spawn_refused'
    ACTION_NATIVE_EXECUTION_SPAWN = 'mcp.servers.native_execution_spawn'
    AUDIT_PATH = '/api/v1/internal/audit_logs'

    def initialize(api_client: nil)
      @api_client = api_client
    end

    def spawn_refused(server, error)
      server_id = server['id']
      return if server_id.blank?

      post_audit(
        action: ACTION_SPAWN_REFUSED,
        resource_id: server_id,
        severity: 'medium',
        metadata: {
          account_id: server['account_id'],
          mcp_server_name: server['name'],
          command: server['command'],
          error_class: error.class.name.split('::').last,
          message: error.message,
          stage: 'worker_validation'
        }
      )
    end

    def native_execution_spawn(mcp_server_id:, account_id:, sandbox_mode:)
      return if mcp_server_id.blank?

      post_audit(
        action: ACTION_NATIVE_EXECUTION_SPAWN,
        resource_id: mcp_server_id,
        severity: 'high',
        metadata: { account_id: account_id, sandbox_mode: sandbox_mode, stage: 'worker_spawn' }
      )
    end

    private

    def post_audit(action:, resource_id:, severity:, metadata:)
      api_client.post(
        AUDIT_PATH,
        audit_log: {
          action: action,
          resource_type: 'McpServer',
          resource_id: resource_id,
          severity: severity,
          risk_level: severity,
          metadata: metadata
        }
      )
    rescue StandardError => e
      logger.error("[Mcp::SpawnAuditReporter] failed to record #{action} for MCP server #{resource_id}: #{e.class}: #{e.message}")
    end

    def api_client
      @api_client ||= BackendApiClient.new
    end

    def logger
      if defined?(PowernodeWorker) && PowernodeWorker.application.respond_to?(:logger)
        PowernodeWorker.application.logger
      else
        require 'logger'
        @logger ||= Logger.new($stdout)
      end
    end
  end
end
