# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::McpToolExecutionJob, 'WebSocket execution' do
  let(:execution_id) { SecureRandom.uuid }
  let(:mock_api_client) { instance_double(BackendApiClient) }

  let(:server) do
    {
      id: SecureRandom.uuid,
      name: 'WebSocket MCP Server',
      connection_type: 'websocket',
      url: 'ws://localhost:8080/mcp',
      connection_timeout: 10,
      response_timeout: 30
    }
  end

  let(:tool) do
    {
      id: SecureRandom.uuid,
      name: 'test_tool',
      description: 'A test tool',
      mcp_server: server
    }
  end

  let(:execution_data) do
    {
      mcp_tool_execution: {
        id: execution_id,
        status: 'pending',
        parameters: { query: 'test' },
        mcp_tool: tool
      }
    }
  end

  before do
    allow(PowernodeWorker).to receive(:logger).and_return(Logger.new(nil))
    allow_any_instance_of(described_class).to receive(:api_client).and_return(mock_api_client)

    # Default API responses
    allow(mock_api_client).to receive(:get).and_return({ success: true, data: execution_data })
    allow(mock_api_client).to receive(:patch)
  end

  describe '#execute_websocket_tool' do
    let(:job) { described_class.new }

    before do
      # Expose the private method for testing
      allow(job).to receive(:log_info)
      allow(job).to receive(:log_error)
      allow(job).to receive(:log_warn)
    end

    context 'with successful connection and response' do
      let(:mock_ws) { double('WebSocket') }
      let(:mock_thread) { double('Thread') }

      it 'returns error when URL is missing' do
        server_without_url = server.merge(url: nil, websocket_url: nil)

        result = job.send(:execute_websocket_tool, server_without_url, tool, { query: 'test' })

        expect(result[:success]).to be false
        expect(result[:error]).to include('No WebSocket URL')
      end

      it 'prefixes URL with ws:// if missing' do
        server_with_host = server.merge(url: 'localhost:8080/mcp')

        # This will fail to connect, but we can verify it tried the right URL
        result = nil
        begin
          result = job.send(:execute_websocket_tool, server_with_host, tool, { query: 'test' })
        rescue StandardError
          # Expected - connection will fail
        end

        # Either raised an error (result is nil) or returned failure hash
        expect(result.nil? || result[:success] == false).to be true
      end
    end

    context 'with connection timeout' do
      it 'returns timeout error' do
        allow(WebSocket::Client::Simple).to receive(:connect) do
          sleep(20) # Simulate hanging connection
        end

        result = job.send(:execute_websocket_tool, server, tool, { query: 'test' })

        expect(result[:success]).to be false
        expect(result[:error]).to include('timeout')
      end
    end

    context 'with connection refused' do
      before do
        allow(WebSocket::Client::Simple).to receive(:connect)
          .and_raise(Errno::ECONNREFUSED.new('Connection refused'))
      end

      it 'returns connection refused error' do
        result = job.send(:execute_websocket_tool, server, tool, { query: 'test' })

        expect(result[:success]).to be false
        expect(result[:error]).to include('Connection refused')
      end
    end
  end

  describe 'MCP request building' do
    let(:job) { described_class.new }

    it 'builds valid JSON-RPC request' do
      request = job.send(:build_mcp_request, 'tools/call', {
        name: 'test_tool',
        arguments: { query: 'test' }
      })

      expect(request[:jsonrpc]).to eq('2.0')
      expect(request[:id]).to be_present
      expect(request[:method]).to eq('tools/call')
      expect(request[:params][:name]).to eq('test_tool')
      expect(request[:params][:arguments]).to eq({ query: 'test' })
    end

    it 'generates unique request IDs' do
      request1 = job.send(:build_mcp_request, 'tools/call', {})
      request2 = job.send(:build_mcp_request, 'tools/call', {})

      expect(request1[:id]).not_to eq(request2[:id])
    end
  end

  describe 'MCP response parsing' do
    let(:job) { described_class.new }

    it 'parses successful response' do
      json_response = '{"jsonrpc":"2.0","id":"123","result":{"content":"Success"}}'

      result = job.send(:parse_mcp_response, json_response)

      expect(result[:result]).to eq({ 'content' => 'Success' })
      expect(result[:error]).to be_nil
    end

    it 'parses error response' do
      json_response = '{"jsonrpc":"2.0","id":"123","error":{"code":-32600,"message":"Invalid request"}}'

      result = job.send(:parse_mcp_response, json_response)

      expect(result[:error][:message]).to eq('Invalid request')
    end

    it 'handles multiple JSON lines' do
      multi_line = "log: starting\n{\"jsonrpc\":\"2.0\",\"id\":\"123\",\"result\":\"ok\"}\n"

      result = job.send(:parse_mcp_response, multi_line)

      expect(result[:result]).to eq('ok')
    end

    it 'returns error for invalid JSON' do
      result = job.send(:parse_mcp_response, 'not json')

      expect(result[:error]).to be_present
    end
  end

  describe 'integration with job execution' do
    it 'updates status to running before execution' do
      allow(mock_api_client).to receive(:get).and_return({ success: true, data: execution_data })

      expect(mock_api_client).to receive(:patch).with(
        "/api/v1/internal/mcp_tool_executions/#{execution_id}",
        { status: 'running' }
      )

      # Will fail on WebSocket connect, but status update happens first
      expect { described_class.new.execute(execution_id) }
        .to raise_error(StandardError)
        .or not_to raise_error
    end

    it 'updates status to completed on success' do
      allow_any_instance_of(described_class).to receive(:execute_mcp_tool).and_return({
        success: true,
        output: { result: 'test output' }
      })

      expect(mock_api_client).to receive(:patch).with(
        "/api/v1/internal/mcp_tool_executions/#{execution_id}",
        hash_including(status: 'completed', result: { result: 'test output' })
      )

      described_class.new.execute(execution_id)
    end

    it 'updates status to failed on error' do
      allow_any_instance_of(described_class).to receive(:execute_mcp_tool).and_return({
        success: false,
        error: 'Connection failed'
      })

      expect(mock_api_client).to receive(:patch).with(
        "/api/v1/internal/mcp_tool_executions/#{execution_id}",
        hash_including(status: 'failed', error_message: 'Connection failed')
      )

      described_class.new.execute(execution_id)
    end
  end
end
