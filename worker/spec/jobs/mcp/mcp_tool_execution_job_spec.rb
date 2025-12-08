# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::McpToolExecutionJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:execution_id) { 'exec-123' }
  let(:server_id) { 'server-456' }
  let(:tool_id) { 'tool-789' }
  let(:job_args) { execution_id }

  let(:tool_data) do
    {
      id: tool_id,
      name: 'search',
      description: 'Search the web',
      mcp_server: {
        id: server_id,
        name: 'Test Server',
        connection_type: 'stdio',
        command: '/usr/bin/mcp-server',
        args: [],
        env: {}
      }
    }
  end

  let(:execution_data) do
    {
      id: execution_id,
      status: 'pending',
      parameters: { query: 'test query' },
      mcp_tool: tool_data
    }
  end

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe 'job configuration' do
    it 'is configured with mcp queue' do
      expect(described_class.sidekiq_options['queue']).to eq('mcp')
    end

    it 'has 3 retries configured' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#execute' do
    let(:job) { described_class.new }
    let(:api_client) { instance_double(BackendApiClient) }

    before do
      allow(job).to receive(:api_client).and_return(api_client)
      allow(job).to receive(:log_info)
      allow(job).to receive(:log_error)
      allow(job).to receive(:log_warn)
    end

    context 'when execution is successful' do
      let(:tool_output) { { results: [{ title: 'Result 1', url: 'http://example.com' }] } }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_tool_executions/#{execution_id}")
          .and_return(success: true, data: { mcp_tool_execution: execution_data })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(job).to receive(:execute_mcp_tool).and_return(
          success: true,
          output: tool_output
        )
      end

      it 'fetches execution details' do
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_tool_executions/#{execution_id}")

        job.execute(execution_id)
      end

      it 'updates status to running' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/mcp_tool_executions/#{execution_id}",
            hash_including(status: 'running')
          )

        job.execute(execution_id)
      end

      it 'executes the MCP tool' do
        expect(job).to receive(:execute_mcp_tool).with(
          tool_data[:mcp_server],
          tool_data,
          execution_data[:parameters]
        )

        job.execute(execution_id)
      end

      it 'updates status to completed with result' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/mcp_tool_executions/#{execution_id}",
            hash_including(status: 'completed', result: tool_output)
          )

        job.execute(execution_id)
      end

      it 'records execution time' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/mcp_tool_executions/#{execution_id}",
            hash_including(:execution_time_ms)
          )

        job.execute(execution_id)
      end

      it 'logs successful completion' do
        expect(job).to receive(:log_info).with(/execution completed/, anything)

        job.execute(execution_id)
      end
    end

    context 'when execution fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_tool_executions/#{execution_id}")
          .and_return(success: true, data: { mcp_tool_execution: execution_data })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(job).to receive(:execute_mcp_tool).and_return(
          success: false,
          error: 'Tool execution timed out'
        )
      end

      it 'updates status to failed with error' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/mcp_tool_executions/#{execution_id}",
            hash_including(status: 'failed', error_message: 'Tool execution timed out')
          )

        job.execute(execution_id)
      end

      it 'logs error' do
        expect(job).to receive(:log_error).with(/execution failed/, anything, anything)

        job.execute(execution_id)
      end
    end

    context 'when API request fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_tool_executions/#{execution_id}")
          .and_return(success: false, error: 'Not found')
      end

      it 'logs error and returns' do
        expect(job).to receive(:log_error).with(/Failed to fetch execution details/, anything, anything)

        job.execute(execution_id)
      end
    end

    context 'with different connection types' do
      context 'stdio execution' do
        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_tool_executions/#{execution_id}")
            .and_return(success: true, data: { mcp_tool_execution: execution_data })
          allow(api_client).to receive(:patch).and_return(success: true)
        end

        it 'executes via stdio' do
          expect(job).to receive(:execute_mcp_tool).and_call_original

          job.execute(execution_id)
        end
      end

      context 'http execution' do
        let(:http_tool_data) do
          tool_data.merge(
            mcp_server: tool_data[:mcp_server].merge(
              connection_type: 'http',
              url: 'http://localhost:3000'
            )
          )
        end

        let(:http_execution_data) { execution_data.merge(mcp_tool: http_tool_data) }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_tool_executions/#{execution_id}")
            .and_return(success: true, data: { mcp_tool_execution: http_execution_data })
          allow(api_client).to receive(:patch).and_return(success: true)
          stub_request(:post, 'http://localhost:3000/tools/call')
            .to_return(
              status: 200,
              body: { result: { data: 'test result' } }.to_json
            )
        end

        it 'executes via HTTP' do
          job.execute(execution_id)
        end
      end

      context 'websocket execution' do
        let(:ws_tool_data) do
          tool_data.merge(
            mcp_server: tool_data[:mcp_server].merge(
              connection_type: 'websocket',
              url: 'ws://localhost:3000'
            )
          )
        end

        let(:ws_execution_data) { execution_data.merge(mcp_tool: ws_tool_data) }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_tool_executions/#{execution_id}")
            .and_return(success: true, data: { mcp_tool_execution: ws_execution_data })
          allow(api_client).to receive(:patch).and_return(success: true)
          # Mock the WebSocket library
          allow(job).to receive(:execute_websocket_tool).and_return(
            success: true,
            output: { result: 'websocket result' }
          )
        end

        it 'executes via WebSocket' do
          job.execute(execution_id)
        end
      end

      context 'unknown connection type' do
        let(:unknown_tool_data) do
          tool_data.merge(
            mcp_server: tool_data[:mcp_server].merge(connection_type: 'grpc')
          )
        end

        let(:unknown_execution_data) { execution_data.merge(mcp_tool: unknown_tool_data) }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_tool_executions/#{execution_id}")
            .and_return(success: true, data: { mcp_tool_execution: unknown_execution_data })
          allow(api_client).to receive(:patch).and_return(success: true)
        end

        it 'fails with unknown connection type error' do
          expect(api_client).to receive(:patch)
            .with(
              "/api/v1/internal/mcp_tool_executions/#{execution_id}",
              hash_including(status: 'failed', error_message: /Unknown connection type/)
            )

          job.execute(execution_id)
        end
      end
    end

    context 'when execution raises exception' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_tool_executions/#{execution_id}")
          .and_return(success: true, data: { mcp_tool_execution: execution_data })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(job).to receive(:execute_mcp_tool).and_raise(StandardError, 'Unexpected error')
      end

      it 'logs error and re-raises' do
        expect(job).to receive(:log_error)

        expect { job.execute(execution_id) }.to raise_error(StandardError)
      end
    end
  end
end
