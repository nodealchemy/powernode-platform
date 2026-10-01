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
    # Round 1: the payload stores WHERE the refusal hit (launcher, argv size,
    # offending index, rule name), never argv or the message — both can
    # carry tokens. Posted with post_no_retry and a 5 s deadline so a slow
    # backend neither holds the refusal nor writes the row twice.
    it 'posts a medium-severity mcp.servers.spawn_refused row with the launcher, arg count, offending index and rule' do
      error = McpSecurityService::CommandNotAllowedError.new('npx: package "pkg" is not pinned', rule: 'package_pin', arg_index: 1)

      expect(api_client).to receive(:post_no_retry).with(
        '/api/v1/internal/audit_logs',
        {
          audit_log: {
            action: 'mcp.servers.spawn_refused',
            resource_type: 'McpServer',
            resource_id: 'srv-1',
            severity: 'medium',
            risk_level: 'medium',
            metadata: {
              account_id: 'acct-1',
              mcp_server_name: 'Filesystem',
              launcher: 'npx',
              arg_count: 2,
              arg_index: 1,
              rule: 'package_pin',
              error_class: 'CommandNotAllowedError',
              stage: 'worker_validation'
            }
          }
        },
        timeout: described_class::AUDIT_TIMEOUT_SECONDS
      )

      reporter.spawn_refused(server, error)
    end

    it 'never serializes argv, the message or env values — the payload carries no token-bearing string' do
      error = McpSecurityService::EnvironmentViolationError.new('Forbidden environment variables detected: LD_PRELOAD')
      tokenful = server.merge('args' => %w[-y pkg --token=super-secret-arg])

      expect(api_client).to receive(:post_no_retry) do |_path, payload, **_opts|
        json = payload.to_json
        expect(json).not_to include('super-secret')
        expect(json).not_to include('super-secret-arg')
        expect(json).not_to include('LD_PRELOAD')
        expect(payload[:audit_log][:metadata].keys).not_to include(:message, :command, :args)
      end

      reporter.spawn_refused(tokenful, error)
    end

    it 'counts command-string tokens in arg_count and names the launcher by basename' do
      error = McpSecurityService::CommandNotAllowedError.new('x', rule: 'launcher_option', arg_index: 0)

      expect(api_client).to receive(:post_no_retry) do |_path, payload, **_opts|
        expect(payload[:audit_log][:metadata]).to include(launcher: 'npx', arg_count: 2, arg_index: 0, rule: 'launcher_option')
      end

      reporter.spawn_refused(server.merge('command' => '/usr/bin/npx -y', 'args' => %w[pkg]), error)
    end

    it 'skips silently when the server has no id (nothing to attach the row to)' do
      expect(api_client).not_to receive(:post_no_retry)

      reporter.spawn_refused(server.except('id'), StandardError.new('x'))
    end

    it 'swallows and logs an API failure instead of raising' do
      allow(api_client).to receive(:post_no_retry).and_raise(BackendApiClient::ApiError.new('boom', 500))

      expect { reporter.spawn_refused(server, StandardError.new('x')) }.not_to raise_error
    end

    it 'swallows a timeout (408) instead of raising — a slow audit sink never holds a refusal' do
      allow(api_client).to receive(:post_no_retry).and_raise(BackendApiClient::ApiError.new('timeout', 408))

      expect { reporter.spawn_refused(server, StandardError.new('x')) }.not_to raise_error
    end
  end

  describe '#native_execution_spawn' do
    it 'posts a high-severity mcp.servers.native_execution_spawn row with post_no_retry and the deadline' do
      expect(api_client).to receive(:post_no_retry).with(
        '/api/v1/internal/audit_logs',
        {
          audit_log: {
            action: 'mcp.servers.native_execution_spawn',
            resource_type: 'McpServer',
            resource_id: 'srv-1',
            severity: 'high',
            risk_level: 'high',
            metadata: { account_id: 'acct-1', sandbox_mode: 'required', stage: 'worker_spawn' }
          }
        },
        timeout: described_class::AUDIT_TIMEOUT_SECONDS
      )

      reporter.native_execution_spawn(mcp_server_id: 'srv-1', account_id: 'acct-1', sandbox_mode: 'required')
    end

    it 'swallows and logs an API failure instead of raising' do
      allow(api_client).to receive(:post_no_retry).and_raise(StandardError, 'boom')

      expect {
        reporter.native_execution_spawn(mcp_server_id: 'srv-1', account_id: 'acct-1', sandbox_mode: 'off')
      }.not_to raise_error
    end

    it 'swallows a timeout (408) — a slow audit sink never holds a native spawn' do
      allow(api_client).to receive(:post_no_retry).and_raise(BackendApiClient::ApiError.new('timeout', 408))

      expect {
        reporter.native_execution_spawn(mcp_server_id: 'srv-1', account_id: 'acct-1', sandbox_mode: 'required')
      }.not_to raise_error
    end
  end

  it 'uses a 5 second audit deadline' do
    expect(described_class::AUDIT_TIMEOUT_SECONDS).to eq(5)
  end
end
