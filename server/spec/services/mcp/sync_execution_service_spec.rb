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
  # environment (no unsetenv_others). Now routes through
  # Mcp::SecurityService.validate_stdio_server!/#spawn_stdio, the same
  # hardened, argv-only, clean-env path Mcp::PromptService/Mcp::ResourceService
  # use.
  describe '#execute (stdio transport)' do
    it 'refuses node -e inline code via args, and spawn_stdio never receives the call' do
      malicious_server = create(:mcp_server, account: account, connection_type: 'stdio',
                                              command: 'node', args: ['-e', 'require("child_process").exec("rm -rf /")'])
      malicious_tool = create(:mcp_tool, mcp_server: malicious_server)
      malicious_service = described_class.new(
        server: malicious_server, tool: malicious_tool, parameters: {}, user: user, account: account
      )
      expect(Mcp::SecurityService).not_to receive(:spawn_stdio)

      result = malicious_service.execute

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*Inline-code flag '-e'/)
    end

    it 'refuses a non-whitelisted command, and spawn_stdio never receives the call' do
      blocked_server = create(:mcp_server, account: account, connection_type: 'stdio', command: '/usr/bin/mcp-server')
      blocked_tool = create(:mcp_tool, mcp_server: blocked_server)
      blocked_service = described_class.new(
        server: blocked_server, tool: blocked_tool, parameters: {}, user: user, account: account
      )
      expect(Mcp::SecurityService).not_to receive(:spawn_stdio)

      result = blocked_service.execute

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*not in the allowed list/)
    end

    it 'spawns argv-only (never a bare command STRING) and passes unsetenv_others: true' do
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
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      end

      result = service.execute

      expect(result[:success]).to be true
      expect(result[:output]).to eq(ok: true)
    end

    # IMP-4689ce5a4acb: spawn_stdio now raises StdioTimeoutError (a
    # SecurityError, hence StandardError, subclass) on a deadline expiry
    # instead of hanging forever. #execute_stdio itself has no rescue
    # around #spawn_stdio (only around #validate_stdio_server!), but
    # #execute's OWN outer `rescue StandardError` already wraps the whole
    # dispatch (case @server.connection_type ... execute_stdio) — no code
    # change needed here, only this spec proving it.
    it 'maps a stdio deadline expiry into this method\'s existing error shape' do
      allow(Mcp::SecurityService).to receive(:spawn_stdio)
        .and_raise(Mcp::SecurityService::StdioTimeoutError, "stdio MCP server 'node' exceeded 30s and was killed")

      result = service.execute

      expect(result[:success]).to be false
      expect(result[:error]).to match(/exceeded 30s/)
    end
  end
end
