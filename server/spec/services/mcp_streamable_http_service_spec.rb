# frozen_string_literal: true

require 'rails_helper'

RSpec.describe McpStreamableHttpService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mcp_server) do
    create(:mcp_server,
           account: account,
           connection_type: 'http',
           auth_type: 'none',
           capabilities: { 'url' => 'https://mcp.example.com/mcp' })
  end

  subject(:service) { described_class.new(server: mcp_server, user: user, account: account) }

  describe '#initialize' do
    it 'creates service with server, user, and account' do
      expect(service).to be_a(described_class)
    end
  end

  describe '#initialize_protocol' do
    context 'with successful connection' do
      let(:init_response) do
        {
          jsonrpc: '2.0',
          id: '123',
          result: {
            protocolVersion: '2025-06-18',
            capabilities: { tools: { listChanged: true } },
            serverInfo: { name: 'Test Server', version: '1.0' }
          }
        }
      end

      before do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_return(
            status: 200,
            body: init_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'sends initialize request with protocol version' do
        result = service.initialize_protocol

        expect(result[:success]).to be true
        expect(result[:result]).to include('protocolVersion', 'capabilities', 'serverInfo')
      end

      it 'includes MCP-Protocol-Version header' do
        service.initialize_protocol

        # Header is sent on both initialize request and initialized notification
        expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
          .with(headers: { 'MCP-Protocol-Version' => '2025-06-18' })
          .at_least_once
      end

      it 'sends initialized notification after success' do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_return(status: 200, body: init_response.to_json, headers: { 'Content-Type' => 'application/json' })

        service.initialize_protocol

        expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
          .with { |req| JSON.parse(req.body)['method'] == 'notifications/initialized' }
          .at_least_once
      end
    end

    context 'with connection failure' do
      before do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_timeout
      end

      it 'raises TimeoutError' do
        expect { service.initialize_protocol }
          .to raise_error(McpStreamableHttpService::TimeoutError)
      end
    end
  end

  describe '#list_tools' do
    let(:tools_response) do
      {
        jsonrpc: '2.0',
        id: '123',
        result: {
          tools: [
            { name: 'search', description: 'Search for files', inputSchema: {} },
            { name: 'read_file', description: 'Read a file', inputSchema: {} }
          ]
        }
      }
    end

    before do
      stub_request(:post, 'https://mcp.example.com/mcp')
        .to_return(status: 200, body: tools_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends tools/list request' do
      result = service.list_tools

      expect(result[:success]).to be true
      expect(result[:result]['tools']).to be_an(Array)
      expect(result[:result]['tools'].length).to eq(2)
    end

    it 'passes cursor parameter when provided' do
      service.list_tools(cursor: 'next_page_token')

      expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
        .with { |req| JSON.parse(req.body)['params']['cursor'] == 'next_page_token' }
    end
  end

  describe '#call_tool' do
    let(:tool_result) do
      {
        jsonrpc: '2.0',
        id: '123',
        result: {
          content: [ { type: 'text', text: 'File contents here' } ],
          isError: false
        }
      }
    end

    before do
      stub_request(:post, 'https://mcp.example.com/mcp')
        .to_return(status: 200, body: tool_result.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends tools/call request with name and arguments' do
      result = service.call_tool(name: 'read_file', arguments: { path: '/tmp/test.txt' })

      expect(result[:success]).to be true
      expect(result[:result]['content']).to be_present
    end

    it 'includes correct JSON-RPC structure' do
      service.call_tool(name: 'search', arguments: { query: 'test' })

      expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
        .with { |req|
          body = JSON.parse(req.body)
          body['method'] == 'tools/call' &&
            body['params']['name'] == 'search' &&
            body['params']['arguments']['query'] == 'test'
        }
    end
  end

  describe '#list_resources' do
    let(:resources_response) do
      {
        jsonrpc: '2.0',
        id: '123',
        result: {
          resources: [
            { uri: 'file:///project/readme.md', name: 'README', mimeType: 'text/markdown' }
          ]
        }
      }
    end

    before do
      stub_request(:post, 'https://mcp.example.com/mcp')
        .to_return(status: 200, body: resources_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends resources/list request' do
      result = service.list_resources

      expect(result[:success]).to be true
      expect(result[:result]['resources']).to be_an(Array)
    end
  end

  describe '#read_resource' do
    let(:resource_response) do
      {
        jsonrpc: '2.0',
        id: '123',
        result: {
          contents: [ { uri: 'file:///test.txt', mimeType: 'text/plain', text: 'content' } ]
        }
      }
    end

    before do
      stub_request(:post, 'https://mcp.example.com/mcp')
        .to_return(status: 200, body: resource_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends resources/read request with URI' do
      result = service.read_resource(uri: 'file:///test.txt')

      expect(result[:success]).to be true
    end
  end

  describe '#list_prompts' do
    let(:prompts_response) do
      {
        jsonrpc: '2.0',
        id: '123',
        result: {
          prompts: [ { name: 'code_review', description: 'Review code' } ]
        }
      }
    end

    before do
      stub_request(:post, 'https://mcp.example.com/mcp')
        .to_return(status: 200, body: prompts_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends prompts/list request' do
      result = service.list_prompts

      expect(result[:success]).to be true
      expect(result[:result]['prompts']).to be_an(Array)
    end
  end

  describe '#get_prompt' do
    let(:prompt_response) do
      {
        jsonrpc: '2.0',
        id: '123',
        result: {
          messages: [ { role: 'user', content: { type: 'text', text: 'Review this code' } } ]
        }
      }
    end

    before do
      stub_request(:post, 'https://mcp.example.com/mcp')
        .to_return(status: 200, body: prompt_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends prompts/get request with name and arguments' do
      result = service.get_prompt(name: 'code_review', arguments: { language: 'ruby' })

      expect(result[:success]).to be true
      expect(result[:result]['messages']).to be_an(Array)
    end
  end

  describe '#ping' do
    before do
      stub_request(:post, 'https://mcp.example.com/mcp')
        .to_return(status: 200, body: { jsonrpc: '2.0', id: '123', result: {} }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends ping request' do
      result = service.ping

      expect(result[:success]).to be true
    end
  end

  describe 'SSE response handling' do
    let(:sse_body) do
      "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":\"123\",\"result\":{\"status\":\"ok\"}}\n\n"
    end

    before do
      stub_request(:post, 'https://mcp.example.com/mcp')
        .to_return(
          status: 200,
          body: sse_body,
          headers: { 'Content-Type' => 'text/event-stream' }
        )
    end

    it 'parses SSE response correctly' do
      result = service.call_tool(name: 'test', arguments: {})

      expect(result[:success]).to be true
      expect(result[:result]).to include('status' => 'ok')
    end
  end

  describe 'error handling' do
    context 'with JSON-RPC error response' do
      before do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_return(
            status: 200,
            body: {
              jsonrpc: '2.0',
              id: '123',
              error: { code: -32600, message: 'Invalid Request' }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns error in result' do
        result = service.list_tools

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid Request')
        expect(result[:error_code]).to eq(-32600)
      end
    end

    context 'with 401 Unauthorized' do
      before do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_return(status: 401, body: 'Unauthorized')
      end

      it 'returns auth failure' do
        result = service.list_tools

        expect(result[:success]).to be false
        expect(result[:code]).to eq(401)
      end
    end

    context 'with 404 Not Found' do
      before do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_return(status: 404, body: 'Not Found')
      end

      it 'returns not found error' do
        result = service.list_tools

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Endpoint not found')
        expect(result[:code]).to eq(404)
      end
    end

    context 'with network error' do
      before do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_raise(Errno::ECONNREFUSED)
      end

      it 'raises ConnectionError' do
        expect { service.list_tools }
          .to raise_error(McpStreamableHttpService::ConnectionError)
      end
    end

    context 'with timeout' do
      before do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_timeout
      end

      it 'raises TimeoutError' do
        expect { service.list_tools }
          .to raise_error(McpStreamableHttpService::TimeoutError)
      end
    end
  end

  describe 'authentication' do
    context 'with api_key auth' do
      let(:mcp_server) do
        create(:mcp_server,
               account: account,
               connection_type: 'http',
               auth_type: 'api_key',
               capabilities: { 'url' => 'https://mcp.example.com/mcp' },
               env: { 'api_key' => 'test_api_key_123' })
      end

      before do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_return(status: 200, body: { jsonrpc: '2.0', id: '123', result: {} }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'includes API key in Authorization header' do
        service.ping

        expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
          .with(headers: { 'Authorization' => 'Bearer test_api_key_123' })
      end
    end

    context 'with custom api_key header' do
      let(:mcp_server) do
        create(:mcp_server,
               account: account,
               connection_type: 'http',
               auth_type: 'api_key',
               capabilities: { 'url' => 'https://mcp.example.com/mcp' },
               env: {
                 'api_key' => 'custom_key',
                 'api_key_header' => 'X-API-Key'
               })
      end

      before do
        stub_request(:post, 'https://mcp.example.com/mcp')
          .to_return(status: 200, body: { jsonrpc: '2.0', id: '123', result: {} }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'uses custom header for API key' do
        service.ping

        expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
          .with(headers: { 'X-API-Key' => 'custom_key' })
      end
    end
  end

  describe 'protocol compliance' do
    before do
      stub_request(:post, 'https://mcp.example.com/mcp')
        .to_return(status: 200, body: { jsonrpc: '2.0', id: '123', result: {} }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'includes required headers' do
      service.ping

      expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
        .with(headers: {
                'Content-Type' => 'application/json',
                'MCP-Protocol-Version' => '2025-06-18'
              })
    end

    it 'requests JSON or SSE responses' do
      service.ping

      expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
        .with(headers: { 'Accept' => 'application/json, text/event-stream' })
    end

    it 'includes jsonrpc version in request' do
      service.ping

      expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
        .with { |req| JSON.parse(req.body)['jsonrpc'] == '2.0' }
    end

    it 'includes request ID' do
      service.ping

      expect(WebMock).to have_requested(:post, 'https://mcp.example.com/mcp')
        .with { |req| JSON.parse(req.body)['id'].present? }
    end
  end

  describe 'error classes' do
    it 'defines StreamableHttpError as base class' do
      expect(McpStreamableHttpService::StreamableHttpError).to be < StandardError
    end

    it 'defines ConnectionError' do
      expect(McpStreamableHttpService::ConnectionError).to be < McpStreamableHttpService::StreamableHttpError
    end

    it 'defines ProtocolError' do
      expect(McpStreamableHttpService::ProtocolError).to be < McpStreamableHttpService::StreamableHttpError
    end

    it 'defines TimeoutError' do
      expect(McpStreamableHttpService::TimeoutError).to be < McpStreamableHttpService::StreamableHttpError
    end
  end

  describe 'MCP_PROTOCOL_VERSION constant' do
    it 'is set to 2025-06-18' do
      expect(described_class::MCP_PROTOCOL_VERSION).to eq('2025-06-18')
    end
  end
end
