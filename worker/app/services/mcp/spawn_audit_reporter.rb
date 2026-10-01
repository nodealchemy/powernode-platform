# frozen_string_literal: true

require 'shellwords'
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
  # The row's account is the WORKER's (the mTLS principal); the server's
  # owning account travels in metadata.account_id.
  #
  # WHAT THE PAYLOAD CARRIES (round 1): where the refusal hit — the
  # launcher (argv[0]'s basename), the resolved argv's size, the offending
  # token's index and the rule name (SecurityError#rule / #arg_index) —
  # plus the error class. NEVER argv, the error message (which quotes
  # argv), `server['env']` or any env value: command-line tokens can be
  # credentials. The only env-related content anywhere is the forbidden
  # KEY name inside the error class, and that is not sent either.
  #
  # Posted with post_no_retry and a short deadline: a slow backend must
  # neither hold a refusal or a native spawn, nor write the row twice when
  # the response is lost. Never raises — an audit failure is logged, not
  # allowed to become a refused (or, worse, an unsandboxed) spawn; the
  # security verdict is decided before this is ever called.
  class SpawnAuditReporter
    ACTION_SPAWN_REFUSED = 'mcp.servers.spawn_refused'
    ACTION_NATIVE_EXECUTION_SPAWN = 'mcp.servers.native_execution_spawn'
    AUDIT_PATH = '/api/v1/internal/audit_logs'
    AUDIT_TIMEOUT_SECONDS = 5

    def initialize(api_client: nil)
      @api_client = api_client
    end

    def spawn_refused(server, error)
      server_id = server['id']
      return if server_id.blank?

      command_tokens = command_tokens_for(server['command'])
      post_audit(
        action: ACTION_SPAWN_REFUSED,
        resource_id: server_id,
        severity: 'medium',
        metadata: {
          account_id: server['account_id'],
          mcp_server_name: server['name'],
          launcher: command_tokens.first.to_s.empty? ? nil : File.basename(command_tokens.first),
          arg_count: command_tokens.drop(1).size + Array(server['args']).size,
          arg_index: error.respond_to?(:arg_index) ? error.arg_index : nil,
          rule: error.respond_to?(:rule) ? error.rule : nil,
          error_class: error.class.name.split('::').last,
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

    # Same tokenization McpSecurityService uses; an unparseable command is
    # judged on a whitespace split (we only need argv[0] and a count).
    def command_tokens_for(command)
      Shellwords.split(command.to_s)
    rescue ArgumentError
      command.to_s.split(/\s+/)
    end

    def post_audit(action:, resource_id:, severity:, metadata:)
      api_client.post_no_retry(
        AUDIT_PATH,
        {
          audit_log: {
            action: action,
            resource_type: 'McpServer',
            resource_id: resource_id,
            severity: severity,
            risk_level: severity,
            metadata: metadata
          }
        },
        timeout: AUDIT_TIMEOUT_SECONDS
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
