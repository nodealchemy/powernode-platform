# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require_relative '../../../app/services/mcp/mcp_transport_client'

RSpec.describe Mcp::McpTransportClient do
  subject(:client) { described_class.new }

  let(:tool) { { id: 'tool-1', name: 'search' } }
  let(:parameters) { { query: 'hello world' } }

  describe '#build_mcp_request' do
    it 'builds a JSON-RPC 2.0 envelope' do
      request = client.build_mcp_request('tools/call', { name: 'search', arguments: parameters })

      expect(request[:jsonrpc]).to eq('2.0')
      expect(request[:method]).to eq('tools/call')
      expect(request[:params]).to eq(name: 'search', arguments: parameters)
      expect(request[:id]).to be_a(String)
      expect(request[:id]).not_to be_empty
    end

    it 'generates a unique id per request' do
      first = client.build_mcp_request('tools/call', {})
      second = client.build_mcp_request('tools/call', {})

      expect(first[:id]).not_to eq(second[:id])
    end
  end

  describe '#parse_mcp_response' do
    it 'extracts and symbolizes the result of a successful response' do
      json = '{"jsonrpc":"2.0","id":"123","result":{"content":"ok"}}'

      parsed = client.parse_mcp_response(json)

      expect(parsed[:result]).to eq(content: 'ok')
      expect(parsed[:error]).to be_nil
    end

    it 'extracts an error response' do
      json = '{"jsonrpc":"2.0","id":"123","error":{"code":-32600,"message":"Invalid request"}}'

      parsed = client.parse_mcp_response(json)

      expect(parsed[:error][:message]).to eq('Invalid request')
    end

    it 'finds the last valid JSON-RPC line amid log noise' do
      noisy = "starting up\n{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"result\":\"ok\"}\n"

      parsed = client.parse_mcp_response(noisy)

      expect(parsed[:result]).to eq('ok')
    end

    it 'returns an error envelope when no valid response is present' do
      parsed = client.parse_mcp_response('not json at all')

      expect(parsed[:error][:message]).to eq('No valid MCP response received')
    end
  end

  describe '#execute (dispatch)' do
    it 'returns an error for an unknown connection type' do
      server = { connection_type: 'grpc' }

      result = client.execute(server, tool, parameters)

      expect(result).to eq(success: false, error: 'Unknown connection type: grpc')
    end

    it 'routes stdio connections to execute_stdio_tool' do
      server = { connection_type: 'stdio' }
      allow(client).to receive(:execute_stdio_tool).and_return(success: true, output: 'stdio')

      expect(client.execute(server, tool, parameters)).to eq(success: true, output: 'stdio')
      expect(client).to have_received(:execute_stdio_tool).with(server, tool, parameters)
    end

    it 'routes http connections to execute_http_tool' do
      server = { connection_type: 'http' }
      allow(client).to receive(:execute_http_tool).and_return(success: true, output: 'http')

      expect(client.execute(server, tool, parameters)).to eq(success: true, output: 'http')
      expect(client).to have_received(:execute_http_tool).with(server, tool, parameters)
    end

    it 'routes websocket connections to execute_websocket_tool' do
      server = { connection_type: 'websocket' }
      allow(client).to receive(:execute_websocket_tool).and_return(success: true, output: 'ws')

      expect(client.execute(server, tool, parameters)).to eq(success: true, output: 'ws')
      expect(client).to have_received(:execute_websocket_tool).with(server, tool, parameters)
    end
  end

  describe '#execute_stdio_tool' do
    # /usr/bin/node is on McpSecurityService::ALLOWED_COMMANDS — these tests
    # exercise the real security validation path (IMP-7046f6e448d6 review
    # item 3), not a stub, so the command must actually be whitelisted for
    # them to reach McpSecurityService.spawn_stdio at all.
    #
    # IMP-4689ce5a4acb: these mock .spawn_stdio itself now, not the Open3
    # call inside it — spawn_stdio's own Open3.popen3/unsetenv_others/
    # pgroup contract is exercised for real by
    # mcp_security_service_spec.rb's real-spawn specs; these tests only
    # care what THIS call site passes in and does with what comes back.
    let(:server) { { connection_type: 'stdio', command: '/usr/bin/node', args: ['--flag'], env: { 'MCP_X' => '1' } } }

    it 'frames the request to stdin and parses a successful response' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      captured_stdin = nil

      allow(McpSecurityService).to receive(:spawn_stdio) do |command, env, args, stdin_data:, **_kwargs|
        expect(env).to include('MCP_X' => '1', 'PATH' => ENV['PATH'])
        expect(command).to eq('/usr/bin/node')
        expect(args).to eq(['--flag'])
        captured_stdin = stdin_data
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      end

      result = client.execute_stdio_tool(server, tool, parameters)

      framed = JSON.parse(captured_stdin)
      expect(framed['jsonrpc']).to eq('2.0')
      expect(framed['method']).to eq('tools/call')
      expect(framed['params']).to eq('name' => 'search', 'arguments' => { 'query' => 'hello world' })

      expect(result).to eq(success: true, output: { ok: true })
    end

    it 'writes only the built JSON-RPC tools/call request to stdin, nothing else (IMP-97b6b1185748 item 5)' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, **_kwargs|
        parsed = JSON.parse(stdin_data)
        expect(parsed['jsonrpc']).to eq('2.0')
        expect(parsed['method']).to eq('tools/call')
        expect(parsed.keys).to match_array(%w[jsonrpc id method params])
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      end

      client.execute_stdio_tool(server, tool, parameters)
    end

    it 'surfaces an MCP error message from the response' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(McpSecurityService).to receive(:spawn_stdio).and_return(
        ['{"jsonrpc":"2.0","id":"1","error":{"message":"boom"}}', '', success_status]
      )

      expect(client.execute_stdio_tool(server, tool, parameters)).to eq(success: false, error: 'boom')
    end

    # IMP-abda86fb39be review — JSON-RPC over stdio is newline-delimited;
    # a line-buffered MCP server needs the trailing "\n" to know the
    # request is complete. A prior version here (and, before it existed,
    # the server's own send_stdio_request) wrote a bare `to_json` with no
    # newline.
    it 'newline-delimits the JSON-RPC request written to stdin' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      captured_stdin = nil

      allow(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, **_kwargs|
        captured_stdin = stdin_data
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      end

      client.execute_stdio_tool(server, tool, parameters)

      expect(captured_stdin).to end_with("\n")
    end

    it 'reports a non-zero process exit' do
      failed_status = instance_double(Process::Status, success?: false, exitstatus: 3)
      allow(McpSecurityService).to receive(:spawn_stdio).and_return(['', 'stderr text', failed_status])

      expect(client.execute_stdio_tool(server, tool, parameters)).to eq(
        success: false, error: 'Process exited with code 3: stderr text'
      )
    end

    # IMP-abda86fb39be review — a misbehaving/verbose MCP child's stderr
    # is bounded before it's returned to the caller (and, via the
    # server's Mcp::WorkerStdioClient, potentially rendered to an end
    # user) — matches the server's own (now-removed) send_stdio_request,
    # which always truncated at the same length.
    it 'truncates a long stderr in the process-exit error message' do
      failed_status = instance_double(Process::Status, success?: false, exitstatus: 1)
      long_stderr = 'x' * 1000
      allow(McpSecurityService).to receive(:spawn_stdio).and_return(['', long_stderr, failed_status])

      result = client.execute_stdio_tool(server, tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error].length).to be < long_stderr.length
      expect(result[:error]).to start_with('Process exited with code 1: ')
    end

    it 'reports a missing command' do
      allow(McpSecurityService).to receive(:spawn_stdio).and_raise(Errno::ENOENT)

      expect(client.execute_stdio_tool(server, tool, parameters)).to eq(
        success: false, error: 'Command not found: /usr/bin/node'
      )
    end

    # IMP-4689ce5a4acb: spawn_stdio now raises StdioTimeoutError (a
    # SecurityError, hence StandardError, subclass) on a deadline expiry
    # instead of hanging forever. #execute_stdio_tool's OWN
    # `rescue StandardError => e` around this call already maps it into
    # this method's existing error shape — no code change needed, only
    # this spec proving it.
    it "maps a stdio deadline expiry into this method's existing error shape" do
      allow(McpSecurityService).to receive(:spawn_stdio)
        .and_raise(McpSecurityService::StdioTimeoutError, "stdio MCP server '/usr/bin/node' exceeded 30s and was killed")

      result = client.execute_stdio_tool(server, tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Execution error:.*exceeded 30s/)
    end

    it 'refuses a non-whitelisted command via the real McpSecurityService, without ever spawning it' do
      blocked_server = server.merge(command: '/usr/bin/mcp-server')
      expect(McpSecurityService).not_to receive(:spawn_stdio)

      result = client.execute_stdio_tool(blocked_server, tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*not in the allowed list/)
    end

    it 'accepts a string-keyed (indifferent-access) server, not just symbol-keyed' do
      indifferent_server = server.with_indifferent_access
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(McpSecurityService).to receive(:spawn_stdio).and_return(
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      )

      expect(client.execute_stdio_tool(indifferent_server, tool, parameters)).to eq(success: true, output: { ok: true })
    end

    it 'passes a string-keyed env to spawn_stdio, never symbol-keyed (would raise TypeError)' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, env, *_rest, **_kwargs|
        expect(env.keys).to all(be_a(String))
        ['{"jsonrpc":"2.0","id":"1","result":{}}', '', success_status]
      end

      client.execute_stdio_tool(server, tool, parameters)
    end

    # IMP-97b6b1185748: validate_command! only ever checked the `command`
    # string — server[:args]/server['args'] reached the spawn point
    # completely unchecked, so a whitelisted command like "node" plus args
    # ["-e", "<code>"] ran arbitrary code. End-to-end coverage (one spawn
    # site, not just the McpSecurityService unit specs) that the shared
    # validate_stdio_server! helper this class already calls now also
    # refuses that.
    it 'refuses node -e inline code via args, without ever spawning it (end-to-end)' do
      malicious_server = server.merge(command: 'node', args: ['-e', 'require("child_process").exec("rm -rf /")'])
      expect(McpSecurityService).not_to receive(:spawn_stdio)

      result = client.execute_stdio_tool(malicious_server, tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Inline-code flag '-e'/)
    end

    it 'still accepts a normal node invocation with ordinary args (end-to-end)' do
      normal_server = server.merge(command: 'node', args: ['server.js', '--port', '3000'])
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |command, _env, args, **_kwargs|
        expect(command).to eq('node')
        expect(args).to eq(['server.js', '--port', '3000'])
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      end

      result = client.execute_stdio_tool(normal_server, tool, parameters)

      expect(result).to eq(success: true, output: { ok: true })
    end

    # IMP-427e98cae0be: Api::V1::Internal::McpToolExecutionsController used
    # to omit `capabilities` from the nested server hash entirely, so
    # McpSecurityService.validate_stdio_server! (called right here) always
    # saw allow_extended_commands/strict_environment as false regardless of
    # what the server was actually configured with. This end-to-end spec
    # exercises exactly the server-hash shape the backend now sends.
    it "refuses an extended-only command (uvx) when the server hash carries no capabilities at all" do
      extended_server = server.merge(command: 'uvx', args: ['mcp-server-git'])
      expect(McpSecurityService).not_to receive(:spawn_stdio)

      result = client.execute_stdio_tool(extended_server, tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*not in the allowed list/)
    end

    it "honors capabilities.allow_extended_commands: true and allows uvx/docker through to spawn_stdio" do
      extended_server = server.merge(
        command: 'uvx', args: ['mcp-server-git'], capabilities: { 'allow_extended_commands' => true }
      )
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |command, _env, _args, **_kwargs|
        expect(command).to eq('uvx')
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      end

      result = client.execute_stdio_tool(extended_server, tool, parameters)

      expect(result).to eq(success: true, output: { ok: true })
    end

    it "still refuses uvx when capabilities is present but allow_extended_commands is absent/false" do
      extended_server = server.merge(command: 'uvx', args: ['mcp-server-git'], capabilities: { 'tools' => true })
      expect(McpSecurityService).not_to receive(:spawn_stdio)

      result = client.execute_stdio_tool(extended_server, tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*not in the allowed list/)
    end

    it "honors capabilities.strict_environment: true and drops a non-allowlisted env var that would otherwise pass through" do
      strict_server = server.merge(env: { 'CUSTOM_VAR' => 'value' }, capabilities: { 'strict_environment' => true })
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, env, *_rest, **_kwargs|
        expect(env).not_to include('CUSTOM_VAR')
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      end

      client.execute_stdio_tool(strict_server, tool, parameters)
    end

    it "without strict_environment, the same non-allowlisted env var DOES pass through (non-strict default)" do
      non_strict_server = server.merge(env: { 'CUSTOM_VAR' => 'value' })
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, env, *_rest, **_kwargs|
        expect(env).to include('CUSTOM_VAR' => 'value')
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      end

      client.execute_stdio_tool(non_strict_server, tool, parameters)
    end
  end

  # IMP-abda86fb39be (MCP isolation Phase 0 T1): #execute_stdio_tool
  # extracted its own validate/spawn/parse body into this new, JSON-RPC-
  # method-agnostic entry point, so the worker's synchronous
  # /api/v1/mcp/execute_stdio endpoint (JobsController, called by the
  # server's Mcp::WorkerStdioClient for prompts/get, prompts/list,
  # resources/read, resources/list — none of which are `tools/call`) can
  # share it instead of a second hand-rolled copy. #execute_stdio_tool's
  # own describe block above already exercises every branch of the shared
  # body (real end-to-end validation refusals, env sanitization, timeout
  # mapping, ...) via its `tools/call`-framed wrapper — these tests only
  # cover what's NEW: that the method-agnostic entry point itself works
  # with a non-tools/call request, and the mandatory-validator contract
  # the endpoint depends on.
  describe '#execute_stdio_request' do
    let(:server) { { connection_type: 'stdio', command: '/usr/bin/node', args: ['--flag'], env: { 'MCP_X' => '1' } } }
    let(:mcp_request) { { jsonrpc: '2.0', id: 'req-1', method: 'prompts/get', params: { name: 'greeting' } } }

    it 'frames the given (non-tools/call) request to stdin and parses a successful response' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      captured_stdin = nil

      allow(McpSecurityService).to receive(:spawn_stdio) do |command, _env, args, stdin_data:, **_kwargs|
        expect(command).to eq('/usr/bin/node')
        expect(args).to eq(['--flag'])
        captured_stdin = stdin_data
        ['{"jsonrpc":"2.0","id":"req-1","result":{"messages":[]}}', '', success_status]
      end

      result = client.execute_stdio_request(server, mcp_request)

      framed = JSON.parse(captured_stdin)
      expect(framed['method']).to eq('prompts/get')
      expect(framed['params']).to eq('name' => 'greeting')
      expect(result).to eq(success: true, output: { messages: [] })
    end

    # IMP-a50680fd53d8 — admin-gated, same trust tier and gating as
    # allow_extended_commands (carried by the IMP-427e98cae0be
    # capabilities serialization allowlist); the SANDBOX itself lives in
    # McpSecurityService.spawn_stdio, not here, but this method is the
    # ONLY place that reads server['capabilities']['allow_network'] and
    # threads it through — a regression here would silently make every
    # server's network policy default to false (fully sandboxed) or
    # true (unintentionally open), whichever way the bug points.
    it "passes allow_network: true through to spawn_stdio when the server's capabilities say so" do
      network_server = server.merge(capabilities: { 'allow_network' => true })
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, allow_network:, **_kwargs|
        expect(allow_network).to be true
        ['{"jsonrpc":"2.0","id":"req-1","result":{}}', '', success_status]
      end

      # Asserting the RETURN VALUE, not just assertions inside the mock
      # block, matters here: execute_stdio_request wraps the spawn_stdio
      # call in its own `rescue StandardError => e`, so if the real call
      # omits the allow_network: keyword the block requires, the resulting
      # ArgumentError is swallowed into an {success: false, error: ...}
      # result rather than surfacing as a spec failure — a test with no
      # post-call assertion would pass either way.
      result = client.execute_stdio_request(network_server, mcp_request)
      expect(result).to eq(success: true, output: {})
    end

    it 'passes allow_network: false through to spawn_stdio when capabilities omit it' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, allow_network:, **_kwargs|
        expect(allow_network).to be false
        ['{"jsonrpc":"2.0","id":"req-1","result":{}}', '', success_status]
      end

      result = client.execute_stdio_request(server, mcp_request)
      expect(result).to eq(success: true, output: {})
    end

    # IMP-bf72723ef161 — same reasoning as allow_network above: this
    # method is the ONLY place that reads
    # server['capabilities']['egress_allowlist'] and threads it through.
    it "passes egress_allowlist through to spawn_stdio when the server's capabilities carry one" do
      allowlisted_server = server.merge(capabilities: { 'egress_allowlist' => [ '10.0.0.0/8' ] })
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, egress_allowlist:, **_kwargs|
        expect(egress_allowlist).to eq([ '10.0.0.0/8' ])
        ['{"jsonrpc":"2.0","id":"req-1","result":{}}', '', success_status]
      end

      # Post-call assertion matters here too — see the allow_network test
      # above for why (execute_stdio_request's own rescue StandardError
      # would otherwise swallow a missing-keyword ArgumentError silently).
      result = client.execute_stdio_request(allowlisted_server, mcp_request)
      expect(result).to eq(success: true, output: {})
    end

    it 'passes a nil egress_allowlist through to spawn_stdio when capabilities omit it' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, egress_allowlist:, **_kwargs|
        expect(egress_allowlist).to be_nil
        ['{"jsonrpc":"2.0","id":"req-1","result":{}}', '', success_status]
      end

      result = client.execute_stdio_request(server, mcp_request)
      expect(result).to eq(success: true, output: {})
    end

    # IMP-bf72723ef161 review — logging the effective allow set needs the
    # server id; this is the only place that has it to pass along.
    it 'passes the server id through to spawn_stdio as mcp_server_id' do
      identified_server = server.merge(id: 'server-abc')
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)

      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, mcp_server_id:, **_kwargs|
        expect(mcp_server_id).to eq('server-abc')
        ['{"jsonrpc":"2.0","id":"req-1","result":{}}', '', success_status]
      end

      result = client.execute_stdio_request(identified_server, mcp_request)
      expect(result).to eq(success: true, output: {})
    end

    # IMP-abda86fb39be review — the worker-side validator is MANDATORY,
    # not defense-in-depth: this endpoint executes a command supplied in
    # the request body under a shared system worker JWT, so
    # McpSecurityService.validate_stdio_server! is the REAL gate, not an
    # extra check behind the server's own (separate-process) early
    # refusal. Stubs spawn_stdio to FAIL THE TEST if it's ever called, so
    # a future change that accidentally skips validation is caught here
    # even if every other assertion happens to still pass.
    it 'refuses a disallowed command and never spawns it' do
      blocked_server = server.merge(command: '/usr/bin/mcp-server')
      allow(McpSecurityService).to receive(:spawn_stdio) { raise 'spawn_stdio must not be called for a refused command' }

      result = client.execute_stdio_request(blocked_server, mcp_request)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*not in the allowed list/)
      expect(McpSecurityService).not_to have_received(:spawn_stdio)
    end

    it 'refuses a forbidden environment variable and never spawns it' do
      forbidden_env_server = server.merge(env: { 'LD_PRELOAD' => '/tmp/evil.so' })
      allow(McpSecurityService).to receive(:spawn_stdio) { raise 'spawn_stdio must not be called for a forbidden env var' }

      result = client.execute_stdio_request(forbidden_env_server, mcp_request)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Security error:.*Forbidden environment variables/)
      expect(McpSecurityService).not_to have_received(:spawn_stdio)
    end
  end

  describe '#execute_http_tool' do
    let(:server) { { connection_type: 'http', url: 'http://mcp.example.test' } }

    it 'posts a framed JSON-RPC request and parses the result' do
      stub = stub_request(:post, 'http://mcp.example.test/tools/call')
             .with(headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' })
             .to_return(status: 200, body: { result: { data: 'value' } }.to_json)

      result = client.execute_http_tool(server, tool, parameters)

      expect(result).to eq(success: true, output: { 'data' => 'value' })
      expect(stub).to have_been_requested
      expect(a_request(:post, 'http://mcp.example.test/tools/call').with do |req|
        body = JSON.parse(req.body)
        body['jsonrpc'] == '2.0' &&
          body['method'] == 'tools/call' &&
          body['params'] == { 'name' => 'search', 'arguments' => { 'query' => 'hello world' } }
      end).to have_been_made
    end

    it 'surfaces an MCP error message from a 2xx body' do
      stub_request(:post, 'http://mcp.example.test/tools/call')
        .to_return(status: 200, body: { error: { message: 'nope' } }.to_json)

      expect(client.execute_http_tool(server, tool, parameters)).to eq(success: false, error: 'nope')
    end

    it 'reports a non-2xx HTTP status' do
      stub_request(:post, 'http://mcp.example.test/tools/call')
        .to_return(status: 500, body: 'server error')

      expect(client.execute_http_tool(server, tool, parameters)).to eq(
        success: false, error: 'HTTP error: 500 - server error'
      )
    end

    it 'wraps transport-level failures' do
      stub_request(:post, 'http://mcp.example.test/tools/call').to_raise(Errno::ECONNREFUSED)

      result = client.execute_http_tool(server, tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error]).to start_with('HTTP request failed:')
    end
  end

  describe '#execute_websocket_tool' do
    let(:server) { { connection_type: 'websocket', url: 'ws://localhost:8080/mcp', connection_timeout: 1, response_timeout: 1 } }

    it 'returns an error when no URL is configured' do
      result = client.execute_websocket_tool(server.merge(url: nil, websocket_url: nil), tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error]).to include('No WebSocket URL')
    end

    it 'prefixes a bare host with ws:// before connecting' do
      expect(WebSocket::Client::Simple).to receive(:connect)
        .with('ws://localhost:8080/mcp')
        .and_raise(Errno::ECONNREFUSED.new('refused'))

      result = client.execute_websocket_tool(server.merge(url: 'localhost:8080/mcp'), tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error]).to include('Connection refused')
    end

    it 'returns a connection-refused error when the socket is refused' do
      allow(WebSocket::Client::Simple).to receive(:connect).and_raise(Errno::ECONNREFUSED.new('refused'))

      result = client.execute_websocket_tool(server, tool, parameters)

      expect(result[:success]).to be false
      expect(result[:error]).to include('Connection refused')
    end
  end
end
