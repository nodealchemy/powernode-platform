# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::McpToolCacheRefreshJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:job_args) { nil }

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
    end

    context 'when servers are connected' do
      let(:servers) do
        [
          { id: 'server-1', name: 'Server 1', status: 'connected' },
          { id: 'server-2', name: 'Server 2', status: 'connected' },
          { id: 'server-3', name: 'Server 3', status: 'connected' }
        ]
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/mcp_servers?status=connected')
          .and_return(success: true, data: { mcp_servers: servers })
        allow(Mcp::McpToolDiscoveryJob).to receive(:perform_async)
      end

      it 'fetches all connected servers' do
        expect(api_client).to receive(:get)
          .with('/api/v1/internal/mcp_servers?status=connected')

        job.execute
      end

      it 'queues tool discovery for each server' do
        expect(Mcp::McpToolDiscoveryJob).to receive(:perform_async).with('server-1')
        expect(Mcp::McpToolDiscoveryJob).to receive(:perform_async).with('server-2')
        expect(Mcp::McpToolDiscoveryJob).to receive(:perform_async).with('server-3')

        job.execute
      end

      it 'logs the number of servers being refreshed' do
        expect(job).to receive(:log_info).with(/3 MCP server/)

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

      it 'does not queue any discovery jobs' do
        expect(Mcp::McpToolDiscoveryJob).not_to receive(:perform_async)

        job.execute
      end
    end

    context 'when API request fails' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/mcp_servers?status=connected')
          .and_return(success: false, error: 'Service unavailable')
      end

      it 'logs error' do
        expect(job).to receive(:log_error).with(/Failed to fetch connected servers/)

        job.execute
      end

      it 'does not queue any discovery jobs' do
        expect(Mcp::McpToolDiscoveryJob).not_to receive(:perform_async)

        job.execute
      end
    end

    context 'when API raises exception' do
      before do
        allow(api_client).to receive(:get)
          .and_raise(BackendApiClient::ApiError.new('Connection failed'))
      end

      it 'logs error and re-raises' do
        expect(job).to receive(:log_error)

        expect { job.execute }.to raise_error(BackendApiClient::ApiError)
      end
    end
  end
end
