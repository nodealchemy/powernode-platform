# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::SyncExecutionService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { create(:mcp_tool, mcp_server: server) }
  let(:server) { create(:mcp_server, account: account, connection_type: 'stdio', command: 'node', args: ['server.js'], env: {}) }
  let(:service) { described_class.new(server: server, tool: tool, parameters: { 'query' => 'hi' }, user: user, account: account) }

  # IMP-176a386fef98 BLOCKER: #execute_stdio used to validate ONLY the bare
  # command STRING (never args), then spawn @server.command as a bare
  # STRING with `*Array(@server.args)` — Process.spawn/Open3 runs a lone
  # command STRING through `/bin/sh -c` when given no additional args, so
  # an empty `args` would have let the command string alone execute
  # arbitrary shell syntax — and inherited this Rails process's full
  # environment (no unsetenv_others). Routed through
  # Mcp::SecurityService.validate_stdio_server! for early refusal.
  #
  # IMP-abda86fb39be (MCP isolation Phase 0 T1): actual execution moved to
  # the worker via Mcp::WorkerStdioClient — mocks target THAT now, not
  # Mcp::SecurityService.spawn_stdio (which no longer exists server-side).
  describe '#execute (stdio transport)' do
    it 'refuses node -e inline code via args, and WorkerStdioClient never receives the call' do
      malicious_server = create(:mcp_server, account: account, connection_type: 'stdio',
                                              command: 'node', args: ['-e', 'require("child_process").exec("rm -rf /")'])
      malicious_tool = create(:mcp_tool, mcp_server: malicious_server)
      malicious_service = described_class.new(
        server: malicious_server, tool: malicious_tool, parameters: {}, user: user, account: account
      )
      expect(Mcp::WorkerStdioClient).not_to receive(:execute)

      result = malicious_service.execute

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*Inline-code flag '-e'/)
    end

    it 'refuses a non-whitelisted command, and WorkerStdioClient never receives the call' do
      blocked_server = create(:mcp_server, account: account, connection_type: 'stdio', command: '/usr/bin/mcp-server')
      blocked_tool = create(:mcp_tool, mcp_server: blocked_server)
      blocked_service = described_class.new(
        server: blocked_server, tool: blocked_tool, parameters: {}, user: user, account: account
      )
      expect(Mcp::WorkerStdioClient).not_to receive(:execute)

      result = blocked_service.execute

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*not in the allowed list/)
    end

    it 'sends the account-scoped request to the worker and parses a successful tools/call response' do
      # IMP-abda86fb39be: mocks Mcp::WorkerStdioClient.execute itself, not
      # the HTTP call inside it — that internal shape (WorkerTransport,
      # the worker's own validate_stdio_server!/spawn_stdio) is exercised
      # for real by worker_stdio_client_spec.rb and the worker's own specs;
      # this test only cares what THIS call site passes in and does with
      # what comes back.
      expect(Mcp::WorkerStdioClient).to receive(:execute) do |account_id:, server:, mcp_request:|
        expect(account_id).to eq(account.id)
        expect(server['command']).to eq('node')
        expect(server['args']).to eq(['server.js'])
        expect(mcp_request[:method]).to eq('tools/call')
        { result: { ok: true } }
      end

      result = service.execute

      expect(result[:success]).to be true
      expect(result[:output]).to eq(ok: true)
    end

    # IMP-4689ce5a4acb / IMP-abda86fb39be: a stdio deadline expiry is now
    # caught INSIDE the worker's own spawn_stdio and returned here as an
    # ordinary `{error:{message:...}}` Hash (not raised across the HTTP
    # boundary as Mcp::SecurityService::StdioTimeoutError, which no longer
    # exists server-side) — handled by #execute_stdio's own
    # `if response[:error]` branch, not #execute's outer
    # `rescue StandardError`. Same final result either way.
    it 'maps a stdio deadline expiry into this method\'s existing error shape' do
      allow(Mcp::WorkerStdioClient).to receive(:execute)
        .and_return(error: { message: "stdio MCP server 'node' exceeded 30s and was killed" })

      result = service.execute

      expect(result[:success]).to be false
      expect(result[:error]).to match(/exceeded 30s/)
    end

    # IMP-abda86fb39be: worker-unreachable is a genuinely NEW failure mode
    # (execution used to be in-process) — WorkerTransport's own errors
    # propagate unrescued from #execute_stdio, so #execute's EXISTING
    # outer `rescue StandardError` is what catches it (and still appends
    # execution_time_ms, as it always has for any StandardError).
    it 'maps a worker-unreachable failure into this method\'s existing error shape' do
      allow(Mcp::WorkerStdioClient).to receive(:execute)
        .and_raise(WorkerTransport::ConnectionError, 'Connection refused')

      result = service.execute

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Connection refused/)
      expect(result[:execution_time_ms]).to be_a(Integer)
    end
  end
end
