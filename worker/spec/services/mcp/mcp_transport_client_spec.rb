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
    let(:server) { { connection_type: 'stdio', command: '/usr/bin/mcp-server', args: ['--flag'], env: { 'MCP_X' => '1' } } }

    it 'frames the request to stdin and parses a successful response' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      captured_stdin = nil

      allow(Open3).to receive(:capture3) do |env, command, *cmd_args, **opts|
        expect(env).to eq('MCP_X' => '1')
        expect(command).to eq('/usr/bin/mcp-server')
        expect(cmd_args).to eq(['--flag'])
        captured_stdin = opts[:stdin_data]
        ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}', '', success_status]
      end

      result = client.execute_stdio_tool(server, tool, parameters)

      framed = JSON.parse(captured_stdin)
      expect(framed['jsonrpc']).to eq('2.0')
      expect(framed['method']).to eq('tools/call')
      expect(framed['params']).to eq('name' => 'search', 'arguments' => { 'query' => 'hello world' })

      expect(result).to eq(success: true, output: { ok: true })
    end

    it 'surfaces an MCP error message from the response' do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return(
        ['{"jsonrpc":"2.0","id":"1","error":{"message":"boom"}}', '', success_status]
      )

      expect(client.execute_stdio_tool(server, tool, parameters)).to eq(success: false, error: 'boom')
    end

    it 'reports a non-zero process exit' do
      failed_status = instance_double(Process::Status, success?: false, exitstatus: 3)
      allow(Open3).to receive(:capture3).and_return(['', 'stderr text', failed_status])

      expect(client.execute_stdio_tool(server, tool, parameters)).to eq(
        success: false, error: 'Process exited with code 3: stderr text'
      )
    end

    it 'reports a missing command' do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

      expect(client.execute_stdio_tool(server, tool, parameters)).to eq(
        success: false, error: 'Command not found: /usr/bin/mcp-server'
      )
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
