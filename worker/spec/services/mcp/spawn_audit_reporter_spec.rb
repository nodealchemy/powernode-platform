# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../app/services/mcp/spawn_audit_reporter'

# IMP-2c760325c102 — the worker's audit sink for stdio spawn events. It
# POSTs through the existing internal audit endpoint
# (/api/v1/internal/audit_logs — the same mechanism every other worker-
# originated audit row uses) and NEVER raises: an audit failure is logged,
# not allowed to turn into a refused or unsandboxed spawn.
RSpec.describe Mcp::SpawnAuditReporter do
  let(:api_client) { instance_double(BackendApiClient) }
  subject(:reporter) { described_class.new(api_client: api_client) }

  let(:server) do
    { 'id' => 'srv-1', 'account_id' => 'acct-1', 'name' => 'Filesystem', 'command' => 'npx', 'args' => %w[-y pkg],
      'env' => { 'MCP_API_KEY' => 'super-secret' }, 'capabilities' => {} }
  end

  describe '#spawn_refused' do
    it 'posts a medium-severity mcp.servers.spawn_refused row naming the server, the error class and message' do
      error = McpSecurityService::CommandNotAllowedError.new('npx: package "pkg" is not pinned to an exact version')

      expect(api_client).to receive(:post).with(
        '/api/v1/internal/audit_logs',
        audit_log: {
          action: 'mcp.servers.spawn_refused',
          resource_type: 'McpServer',
          resource_id: 'srv-1',
          severity: 'medium',
          risk_level: 'medium',
          metadata: {
            account_id: 'acct-1',
            mcp_server_name: 'Filesystem',
            command: 'npx',
            error_class: 'CommandNotAllowedError',
            message: 'npx: package "pkg" is not pinned to an exact version',
            stage: 'worker_validation'
          }
        }
      )

      reporter.spawn_refused(server, error)
    end

    it 'never serializes env values — the payload names no secret' do
      error = McpSecurityService::EnvironmentViolationError.new('Forbidden environment variables detected: LD_PRELOAD')

      expect(api_client).to receive(:post) do |_path, payload|
        expect(payload.to_json).not_to include('super-secret')
      end

      reporter.spawn_refused(server, error)
    end

    it 'skips silently when the server has no id (nothing to attach the row to)' do
      expect(api_client).not_to receive(:post)

      reporter.spawn_refused(server.except('id'), StandardError.new('x'))
    end

    it 'swallows and logs an API failure instead of raising' do
      allow(api_client).to receive(:post).and_raise(BackendApiClient::ApiError.new('boom', 500))

      expect { reporter.spawn_refused(server, StandardError.new('x')) }.not_to raise_error
    end
  end

  describe '#native_execution_spawn' do
    it 'posts a high-severity mcp.servers.native_execution_spawn row' do
      expect(api_client).to receive(:post).with(
        '/api/v1/internal/audit_logs',
        audit_log: {
          action: 'mcp.servers.native_execution_spawn',
          resource_type: 'McpServer',
          resource_id: 'srv-1',
          severity: 'high',
          risk_level: 'high',
          metadata: { account_id: 'acct-1', sandbox_mode: 'required', stage: 'worker_spawn' }
        }
      )

      reporter.native_execution_spawn(mcp_server_id: 'srv-1', account_id: 'acct-1', sandbox_mode: 'required')
    end

    it 'swallows and logs an API failure instead of raising' do
      allow(api_client).to receive(:post).and_raise(StandardError, 'boom')

      expect {
        reporter.native_execution_spawn(mcp_server_id: 'srv-1', account_id: 'acct-1', sandbox_mode: 'off')
      }.not_to raise_error
    end
  end
end
