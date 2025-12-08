# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::McpServerConnectionJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:server_id) { 'server-123' }
  let(:job_args) { [server_id, { 'action' => 'connect' }] }

  let(:server_data) do
    {
      id: server_id,
      name: 'Test MCP Server',
      connection_type: 'stdio',
      command: '/usr/bin/mcp-server',
      args: ['--mode', 'stdio'],
      env: { 'MCP_TOKEN' => 'test' },
      status: 'disconnected'
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

    context 'when connecting to a server' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return(success: true, data: { mcp_server: server_data })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(Mcp::McpToolDiscoveryJob).to receive(:perform_async)
      end

      context 'with successful connection' do
        before do
          allow(job).to receive(:establish_connection).and_return(
            success: true,
            capabilities: { 'tools' => true, 'resources' => false }
          )
        end

        it 'fetches server details from API' do
          expect(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")

          job.execute(server_id, { 'action' => 'connect' })
        end

        it 'updates server status to connected' do
          expect(api_client).to receive(:patch)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}",
              hash_including(status: 'connected')
            )

          job.execute(server_id, { 'action' => 'connect' })
        end

        it 'stores server capabilities' do
          expect(api_client).to receive(:patch)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}",
              hash_including(capabilities: { 'tools' => true, 'resources' => false })
            )

          job.execute(server_id, { 'action' => 'connect' })
        end

        it 'triggers tool discovery job' do
          expect(Mcp::McpToolDiscoveryJob).to receive(:perform_async).with(server_id)

          job.execute(server_id, { 'action' => 'connect' })
        end
      end

      context 'with failed connection' do
        before do
          allow(job).to receive(:establish_connection).and_return(
            success: false,
            error: 'Connection refused'
          )
        end

        it 'updates server status to error' do
          expect(api_client).to receive(:patch)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}",
              hash_including(status: 'error', last_error: 'Connection refused')
            )

          job.execute(server_id, { 'action' => 'connect' })
        end

        it 'does not trigger tool discovery' do
          expect(Mcp::McpToolDiscoveryJob).not_to receive(:perform_async)

          job.execute(server_id, { 'action' => 'connect' })
        end
      end
    end

    context 'when disconnecting from a server' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return(success: true, data: { mcp_server: server_data.merge(status: 'connected') })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(job).to receive(:cleanup_connection).and_return(true)
      end

      it 'updates server status to disconnected' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/mcp_servers/#{server_id}",
            hash_including(status: 'disconnected')
          )

        job.execute(server_id, { 'action' => 'disconnect' })
      end

      it 'performs connection cleanup' do
        expect(job).to receive(:cleanup_connection)

        job.execute(server_id, { 'action' => 'disconnect' })
      end
    end

    context 'when API request fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return(success: false, error: 'Not found')
      end

      it 'logs error and returns' do
        expect(job).to receive(:log_error).with(/Failed to fetch server details/, anything, anything)

        job.execute(server_id, { 'action' => 'connect' })
      end
    end

    context 'with unknown action' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return(success: true, data: { mcp_server: server_data })
      end

      it 'logs error for unknown action' do
        expect(job).to receive(:log_error).with(/Unknown action/, anything, anything)

        job.execute(server_id, { 'action' => 'invalid' })
      end
    end

    context 'with different connection types' do
      context 'stdio connection' do
        before do
          # Define McpSecurityService stub if it doesn't exist
          stub_const('McpSecurityService', Class.new do
            class CommandNotAllowedError < StandardError; end
            class EnvironmentViolationError < StandardError; end
            def self.validate_stdio_execution!(**args)
              { env: args[:env] || {} }
            end
          end)
        end

        it 'establishes stdio connection' do
          allow(api_client).to receive(:get)
            .and_return(success: true, data: { mcp_server: server_data })
          allow(api_client).to receive(:patch).and_return(success: true)
          allow(Mcp::McpToolDiscoveryJob).to receive(:perform_async)

          expect(job).to receive(:establish_connection).and_call_original

          # This will fail because the command doesn't exist, but tests the path
          job.execute(server_id, { 'action' => 'connect' })
        end
      end

      context 'websocket connection' do
        let(:ws_server_data) { server_data.merge(connection_type: 'websocket', url: 'ws://localhost:3000') }

        before do
          allow(api_client).to receive(:get)
            .and_return(success: true, data: { mcp_server: ws_server_data })
          allow(api_client).to receive(:patch).and_return(success: true)
          allow(Mcp::McpToolDiscoveryJob).to receive(:perform_async)
        end

        it 'handles websocket connection type' do
          job.execute(server_id, { 'action' => 'connect' })
        end
      end

      context 'http connection' do
        let(:http_server_data) { server_data.merge(connection_type: 'http', url: 'http://localhost:3000') }

        before do
          allow(api_client).to receive(:get)
            .and_return(success: true, data: { mcp_server: http_server_data })
          allow(api_client).to receive(:patch).and_return(success: true)
          allow(Mcp::McpToolDiscoveryJob).to receive(:perform_async)
          stub_request(:post, 'http://localhost:3000/initialize')
            .to_return(status: 200, body: { result: { capabilities: {} } }.to_json)
        end

        it 'handles http connection type' do
          job.execute(server_id, { 'action' => 'connect' })
        end
      end
    end
  end
end
