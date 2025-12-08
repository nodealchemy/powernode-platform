# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::McpServerHealthCheckJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:server_id) { 'server-123' }
  let(:job_args) { server_id }

  let(:server_data) do
    {
      id: server_id,
      name: 'Test MCP Server',
      connection_type: 'stdio',
      command: '/usr/bin/mcp-server',
      args: [],
      env: {},
      status: 'connected'
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

    it 'has 2 retries configured' do
      expect(described_class.sidekiq_options['retry']).to eq(2)
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

    context 'when checking all servers' do
      let(:servers) do
        [
          { id: 'server-1', name: 'Server 1', status: 'connected' },
          { id: 'server-2', name: 'Server 2', status: 'connected' }
        ]
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/mcp_servers?status=connected')
          .and_return(success: true, data: { mcp_servers: servers })
        allow(described_class).to receive(:perform_async)
      end

      it 'fetches all connected servers' do
        expect(api_client).to receive(:get)
          .with('/api/v1/internal/mcp_servers?status=connected')

        job.execute
      end

      it 'queues health checks for each server' do
        expect(described_class).to receive(:perform_async).with('server-1')
        expect(described_class).to receive(:perform_async).with('server-2')

        job.execute
      end

      it 'logs the number of servers being checked' do
        expect(job).to receive(:log_info).with(/2 MCP server/)

        job.execute
      end
    end

    context 'when no servers are connected' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/mcp_servers?status=connected')
          .and_return(success: true, data: { mcp_servers: [] })
      end

      it 'logs that no servers are available' do
        expect(job).to receive(:log_info).with(/No connected MCP servers/)

        job.execute
      end

      it 'does not queue any health checks' do
        expect(described_class).not_to receive(:perform_async)

        job.execute
      end
    end

    context 'when checking a single server' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return(success: true, data: { mcp_server: server_data })
        allow(api_client).to receive(:post).and_return(success: true)
      end

      context 'with healthy server' do
        before do
          allow(job).to receive(:ping_server).and_return(healthy: true)
        end

        it 'reports health result to API' do
          expect(api_client).to receive(:post)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}/health_result",
              hash_including(healthy: true)
            )

          job.execute(server_id)
        end

        it 'includes latency in health result' do
          expect(api_client).to receive(:post)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}/health_result",
              hash_including(:latency_ms)
            )

          job.execute(server_id)
        end

        it 'logs successful health check' do
          expect(job).to receive(:log_info).with(/health check passed/, anything)

          job.execute(server_id)
        end
      end

      context 'with unhealthy server' do
        before do
          allow(job).to receive(:ping_server).and_return(healthy: false, error: 'Connection refused')
        end

        it 'reports unhealthy status to API' do
          expect(api_client).to receive(:post)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}/health_result",
              hash_including(healthy: false)
            )

          job.execute(server_id)
        end

        it 'logs failed health check with error' do
          expect(job).to receive(:log_warn).with(/health check failed/, anything)

          job.execute(server_id)
        end
      end

      context 'when server is not connected' do
        let(:disconnected_server) { server_data.merge(status: 'disconnected') }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return(success: true, data: { mcp_server: disconnected_server })
        end

        it 'skips health check' do
          expect(job).not_to receive(:ping_server)
          expect(job).to receive(:log_info).with(/server not connected/, anything)

          job.execute(server_id)
        end
      end
    end

    context 'when API request fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return(success: false, error: 'Not found')
      end

      it 'logs error' do
        expect(job).to receive(:log_error).with(/Failed to fetch server details/, anything, anything)

        job.execute(server_id)
      end
    end

    context 'with different connection types' do
      context 'stdio server' do
        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return(success: true, data: { mcp_server: server_data })
          allow(api_client).to receive(:post).and_return(success: true)
        end

        it 'pings stdio server' do
          expect(job).to receive(:ping_server).and_call_original

          job.execute(server_id)
        end
      end

      context 'http server' do
        let(:http_server_data) { server_data.merge(connection_type: 'http', url: 'http://localhost:3000') }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return(success: true, data: { mcp_server: http_server_data })
          allow(api_client).to receive(:post).and_return(success: true)
          stub_request(:post, 'http://localhost:3000/ping')
            .to_return(status: 200, body: '{}')
        end

        it 'pings http server' do
          job.execute(server_id)
        end
      end
    end
  end
end
