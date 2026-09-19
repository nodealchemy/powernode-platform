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
    it 'refuses node -e inline code via args, and Open3 never receives the call' do
      malicious_server = create(:mcp_server, account: account, connection_type: 'stdio',
                                              command: 'node', args: ['-e', 'require("child_process").exec("rm -rf /")'])
      malicious_service = described_class.new(server: malicious_server, account: account)
      expect(Open3).not_to receive(:capture3)

      result = malicious_service.read_resource('file:///etc/passwd')

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*Inline-code flag '-e'/)
    end

    it 'refuses a non-whitelisted command, and Open3 never receives the call' do
      blocked_server = create(:mcp_server, account: account, connection_type: 'stdio', command: '/usr/bin/mcp-server')
      blocked_service = described_class.new(server: blocked_server, account: account)
      expect(Open3).not_to receive(:capture3)

      result = blocked_service.read_resource('file:///etc/passwd')

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*not in the allowed list/)
    end

    it 'executes a whitelisted stdio command and parses a successful resources/read response' do
      success_status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3) do |env, command, *args, **opts|
        expect(command).to eq(['node', 'node'])
        expect(args).to eq(['server.js'])
        expect(env.keys).to all(be_a(String))
        expect(opts[:unsetenv_others]).to be true
        ['{"jsonrpc":"2.0","id":"1","result":{"contents":[{"uri":"file:///a.txt","text":"hello"}]}}', '', success_status]
      end

      result = service.read_resource('file:///a.txt')

      expect(result[:success]).to be true
      expect(result[:content]).to eq('hello')
      expect(result[:uri]).to eq('file:///a.txt')
    end
  end
end
