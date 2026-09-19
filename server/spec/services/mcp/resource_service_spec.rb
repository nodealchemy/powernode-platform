# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::ResourceService do
  let(:account) { create(:account) }
  let(:server) { create(:mcp_server, account: account, connection_type: 'stdio', command: 'node', args: ['server.js'], env: {}) }
  let(:service) { described_class.new(server: server, account: account) }

  # IMP-176a386fef98 BLOCKER: #send_stdio_request used to Open3 @server.
  # command/args/env with NO validation at all — no command whitelist, no
  # argv inline-code check, no env sanitization — reachable from the
  # user-facing resources controller. Now routes through
  # Mcp::SecurityService.validate_stdio_server!/#spawn_stdio, the same
  # hardened path the worker and Mcp::SyncExecutionService/Mcp::PromptService
  # use.
  describe '#read_resource (stdio transport)' do
    it 'refuses node -e inline code via args, and spawn_stdio never receives the call' do
      malicious_server = create(:mcp_server, account: account, connection_type: 'stdio',
                                              command: 'node', args: ['-e', 'require("child_process").exec("rm -rf /")'])
      malicious_service = described_class.new(server: malicious_server, account: account)
      expect(Mcp::SecurityService).not_to receive(:spawn_stdio)

      result = malicious_service.read_resource('file:///etc/passwd')

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*Inline-code flag '-e'/)
    end

    it 'refuses a non-whitelisted command, and spawn_stdio never receives the call' do
      blocked_server = create(:mcp_server, account: account, connection_type: 'stdio', command: '/usr/bin/mcp-server')
      blocked_service = described_class.new(server: blocked_server, account: account)
      expect(Mcp::SecurityService).not_to receive(:spawn_stdio)

      result = blocked_service.read_resource('file:///etc/passwd')

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*not in the allowed list/)
    end

    it 'executes a whitelisted stdio command and parses a successful resources/read response' do
      success_status = instance_double(Process::Status, success?: true)
      # IMP-4689ce5a4acb: mocks .spawn_stdio itself, not the Open3 call
      # inside it — that internal shape (Open3.popen3 + argv0 tuple +
      # unsetenv_others/pgroup) is spawn_stdio's OWN contract, exercised
      # for real by security_service_spec.rb's real-spawn specs; this
      # test only cares what THIS call site passes in and does with what
      # comes back.
      expect(Mcp::SecurityService).to receive(:spawn_stdio) do |command, env, args, stdin_data:|
        expect(command).to eq('node')
        expect(args).to eq(['server.js'])
        expect(env.keys).to all(be_a(String))
        expect(stdin_data).to be_present
        ['{"jsonrpc":"2.0","id":"1","result":{"contents":[{"uri":"file:///a.txt","text":"hello"}]}}', '', success_status]
      end

      result = service.read_resource('file:///a.txt')

      expect(result[:success]).to be true
      expect(result[:content]).to eq('hello')
      expect(result[:uri]).to eq('file:///a.txt')
    end

    # IMP-4689ce5a4acb: spawn_stdio now raises StdioTimeoutError (a
    # SecurityError, hence StandardError, subclass) on a deadline expiry
    # instead of hanging forever. #send_stdio_request itself has no
    # rescue around #spawn_stdio (only around #validate_stdio_server!),
    # but #read_resource's OWN outer `rescue StandardError` already wraps
    # the whole call chain — no code change needed here, only this spec
    # proving it, matching this method's OTHER error-shape tests.
    it 'maps a stdio deadline expiry into this method\'s existing error shape' do
      allow(Mcp::SecurityService).to receive(:spawn_stdio)
        .and_raise(Mcp::SecurityService::StdioTimeoutError, "stdio MCP server 'node' exceeded 30s and was killed")

      result = service.read_resource('file:///a.txt')

      expect(result[:success]).to be false
      expect(result[:error]).to match(/exceeded 30s/)
    end
  end
end
