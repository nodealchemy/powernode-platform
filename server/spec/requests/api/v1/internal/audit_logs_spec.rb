# frozen_string_literal: true

require 'rails_helper'

# IMP-2c760325c102 — the worker→server audit contract for stdio spawn
# events: Mcp::SpawnAuditReporter (worker/app/services/mcp/spawn_audit_reporter.rb)
# POSTs exactly these payloads to this endpoint. Proves the two agree —
# the mTLS worker's account lands on the row, the action passes the
# allowlist, severity/risk/metadata round-trip — because the reporter
# itself swallows every failure, so a disagreement here would make the
# production audit sink fail silently.
RSpec.describe 'Api::V1::Internal::AuditLogs', type: :request do
  let(:account) { create(:account) }
  let(:mcp_server) { create(:mcp_server, account: account, command: 'node', args: [ 'server.js' ]) }
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  describe 'POST /api/v1/internal/audit_logs (the worker spawn-audit payloads)' do
    it 'records mcp.servers.spawn_refused as the reporter sends it' do
      payload = {
        audit_log: {
          action: 'mcp.servers.spawn_refused',
          resource_type: 'McpServer',
          resource_id: mcp_server.id,
          severity: 'medium',
          risk_level: 'medium',
          metadata: {
            account_id: account.id, mcp_server_name: mcp_server.name, launcher: 'npx', arg_count: 2, arg_index: 1,
            rule: 'package_pin', error_class: 'CommandNotAllowedError', stage: 'worker_validation'
          }
        }
      }

      expect {
        post '/api/v1/internal/audit_logs', params: payload, headers: internal_headers, as: :json
      }.to change { AuditLog.where(action: 'mcp.servers.spawn_refused').count }.by(1)

      expect(response).to have_http_status(:created)
      row = AuditLog.where(action: 'mcp.servers.spawn_refused').last
      expect(row.account_id).to eq(account.id)
      expect(row.resource_type).to eq('McpServer')
      expect(row.resource_id).to eq(mcp_server.id)
      expect(row.user_id).to be_nil
      expect(row.source).to eq('worker')
      expect(row.severity).to eq('medium')
      expect(row.risk_level).to eq('medium')
      expect(row.metadata).to include('launcher' => 'npx', 'arg_count' => 2, 'arg_index' => 1, 'rule' => 'package_pin',
                                      'error_class' => 'CommandNotAllowedError', 'stage' => 'worker_validation')
      # the worker's mTLS account is the row's account; the owner travels in metadata
      expect(row.metadata['account_id']).to eq(account.id)
    end

    it 'records mcp.servers.native_execution_spawn as the reporter sends it' do
      payload = {
        audit_log: {
          action: 'mcp.servers.native_execution_spawn',
          resource_type: 'McpServer',
          resource_id: mcp_server.id,
          severity: 'high',
          risk_level: 'high',
          metadata: { account_id: account.id, sandbox_mode: 'required', stage: 'worker_spawn' }
        }
      }

      expect {
        post '/api/v1/internal/audit_logs', params: payload, headers: internal_headers, as: :json
      }.to change { AuditLog.where(action: 'mcp.servers.native_execution_spawn', resource_id: mcp_server.id).count }.by(1)

      expect(response).to have_http_status(:created)
      row = AuditLog.where(action: 'mcp.servers.native_execution_spawn').last
      expect(row.account_id).to eq(account.id)
      expect(row.severity).to eq('high')
      expect(row.metadata).to include('sandbox_mode' => 'required', 'stage' => 'worker_spawn')
    end

    it 'refuses an action outside the audit allowlist with 422, never a 500' do
      payload = { audit_log: { action: 'mcp.servers.not_a_real_action', resource_type: 'McpServer', resource_id: mcp_server.id } }

      post '/api/v1/internal/audit_logs', params: payload, headers: internal_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'is refused without worker authentication' do
      post '/api/v1/internal/audit_logs',
           params: { audit_log: { action: 'mcp.servers.spawn_refused', resource_type: 'McpServer', resource_id: mcp_server.id } },
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
