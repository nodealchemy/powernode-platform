# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::PromptService do
  let(:account) { create(:account) }
  let(:server) { create(:mcp_server, account: account, connection_type: 'stdio', command: 'node', args: ['server.js'], env: {}) }
  let(:service) { described_class.new(server: server, account: account) }

  # IMP-176a386fef98 BLOCKER: #send_stdio_request used to Open3 @server.
  # command/args/env with NO validation at all — no command whitelist, no
  # argv inline-code check, no env sanitization — reachable from the
  # user-facing prompts controller. Routed through
  # Mcp::SecurityService.validate_stdio_server! for early refusal.
  #
  # IMP-abda86fb39be (MCP isolation Phase 0 T1): actual execution moved to
  # the worker via Mcp::WorkerStdioClient — mocks target THAT now, not
  # Mcp::SecurityService.spawn_stdio (which no longer exists server-side).
  describe '#execute_prompt (stdio transport)' do
    it 'refuses node -e inline code via args, and WorkerStdioClient never receives the call' do
      malicious_server = create(:mcp_server, account: account, connection_type: 'stdio',
                                              command: 'node', args: ['-e', 'require("child_process").exec("rm -rf /")'])
      malicious_service = described_class.new(server: malicious_server, account: account)
      expect(Mcp::WorkerStdioClient).not_to receive(:execute)

      result = malicious_service.execute_prompt('greeting', {})

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*Inline-code flag '-e'/)
    end

    it 'refuses a non-whitelisted command, and WorkerStdioClient never receives the call' do
      blocked_server = create(:mcp_server, account: account, connection_type: 'stdio', command: '/usr/bin/mcp-server')
      blocked_service = described_class.new(server: blocked_server, account: account)
      expect(Mcp::WorkerStdioClient).not_to receive(:execute)

      result = blocked_service.execute_prompt('greeting', {})

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*not in the allowed list/)
    end

    it 'executes a whitelisted stdio command via the worker and parses a successful prompts/get response' do
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
        expect(mcp_request[:method]).to eq('prompts/get')
        { result: { messages: [{ role: 'user', content: 'hi' }] } }
      end

      result = service.execute_prompt('greeting', { 'name' => 'world' })

      expect(result[:success]).to be true
      expect(result[:messages]).to eq([{ role: 'user', content: 'hi' }])
    end

    # IMP-4689ce5a4acb / IMP-abda86fb39be: a stdio deadline expiry is now
    # caught INSIDE the worker's own spawn_stdio and returned here as an
    # ordinary `{error:{message:...}}` Hash (not raised across the HTTP
    # boundary as Mcp::SecurityService::StdioTimeoutError, which no longer
    # exists server-side) — handled by the `if response[:error]` branch
    # inside #execute_prompt, not its outer `rescue StandardError`. Same
    # final result either way.
    it 'maps a stdio deadline expiry into this method\'s existing error shape' do
      allow(Mcp::WorkerStdioClient).to receive(:execute)
        .and_return(error: { message: "stdio MCP server 'node' exceeded 30s and was killed" })

      result = service.execute_prompt('greeting', {})

      expect(result[:success]).to be false
      expect(result[:error]).to match(/exceeded 30s/)
    end

    # IMP-abda86fb39be: worker-unreachable is a genuinely NEW failure mode
    # (execution used to be in-process) — WorkerTransport's own errors
    # propagate unrescued from #send_stdio_request, so #execute_prompt's
    # EXISTING outer `rescue StandardError` is what catches it.
    it 'maps a worker-unreachable failure into this method\'s existing error shape' do
      allow(Mcp::WorkerStdioClient).to receive(:execute)
        .and_raise(WorkerTransport::ConnectionError, 'Connection refused')

      result = service.execute_prompt('greeting', {})

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Connection refused/)
    end
  end
end
