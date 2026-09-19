# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::McpToolDiscoveryJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:server_id) { 'server-123' }
  let(:job_args) { server_id }

  let(:server_data) do
    {
      'id' => server_id,
      'name' => 'Test MCP Server',
      'connection_type' => 'stdio',
      'command' => '/usr/bin/mcp-server',
      'args' => [],
      'env' => {},
      'status' => 'connected'
    }
  end

  let(:discovered_tools) do
    [
      { name: 'search', description: 'Search the web', inputSchema: { type: 'object' } },
      { name: 'calculate', description: 'Perform calculations', inputSchema: { type: 'object' } }
    ]
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
      expect(described_class.sidekiq_options['queue'].to_s).to eq('mcp')
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

    context 'when discovering tools successfully' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return('success' => true, 'data' => { 'mcp_server' => server_data })
        allow(job).to receive(:discover_tools_from_server).and_return(
          success: true,
          tools: discovered_tools
        )
        allow(api_client).to receive(:post)
          .with("/api/v1/internal/mcp_servers/#{server_id}/register_tools", anything)
          .and_return('success' => true)
      end

      it 'fetches server details' do
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")

        job.execute(server_id)
      end

      it 'discovers tools from server' do
        expect(job).to receive(:discover_tools_from_server).with(server_data)

        job.execute(server_id)
      end

      it 'registers discovered tools with backend' do
        expect(api_client).to receive(:post)
          .with(
            "/api/v1/internal/mcp_servers/#{server_id}/register_tools",
            hash_including(tools: an_instance_of(Array))
          )

        job.execute(server_id)
      end

      it 'logs success with tool count' do
        expect(job).to receive(:log_info).with(/tools discovered and registered/, anything)

        job.execute(server_id)
      end
    end

    context 'when no tools are discovered' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return('success' => true, 'data' => { 'mcp_server' => server_data })
        allow(job).to receive(:discover_tools_from_server).and_return(
          success: true,
          tools: []
        )
      end

      it 'logs that no tools were found' do
        expect(job).to receive(:log_info).with(/No tools discovered/, anything)

        job.execute(server_id)
      end

      it 'does not register empty tool list' do
        expect(api_client).not_to receive(:post)
          .with("/api/v1/internal/mcp_servers/#{server_id}/register_tools", anything)

        job.execute(server_id)
      end
    end

    context 'when server is not connected' do
      let(:disconnected_server) { server_data.merge('status' => 'disconnected') }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return('success' => true, 'data' => { 'mcp_server' => disconnected_server })
      end

      it 'skips discovery' do
        expect(job).not_to receive(:discover_tools_from_server)
        expect(job).to receive(:log_warn).with(/server not connected/, anything)

        job.execute(server_id)
      end
    end

    context 'when tool discovery fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return('success' => true, 'data' => { 'mcp_server' => server_data })
        allow(job).to receive(:discover_tools_from_server).and_return(
          success: false,
          error: 'MCP protocol error'
        )
      end

      it 'logs error' do
        expect(job).to receive(:log_error).with(/Tool discovery failed/, anything, anything)

        job.execute(server_id)
      end
    end

    context 'when registration fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return('success' => true, 'data' => { 'mcp_server' => server_data })
        allow(job).to receive(:discover_tools_from_server).and_return(
          success: true,
          tools: discovered_tools
        )
        allow(api_client).to receive(:post)
          .with("/api/v1/internal/mcp_servers/#{server_id}/register_tools", anything)
          .and_return('success' => false, 'error' => 'Registration failed')
      end

      it 'logs error with the string-keyed error message' do
        expect(job).to receive(:log_error)
          .with(/Failed to register discovered tools/, nil, hash_including(error: 'Registration failed'))

        job.execute(server_id)
      end
    end

    context 'when API request fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/mcp_servers/#{server_id}")
          .and_return('success' => false, 'error' => 'Not found')
      end

      it 'logs error and returns' do
        expect(job).to receive(:log_error).with(/Failed to fetch server details/, anything, anything)

        job.execute(server_id)
      end
    end

    context 'with different connection types' do
      context 'stdio server' do
        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => server_data })
        end

        it 'refuses a non-whitelisted stdio command via the real McpSecurityService' do
          # server_data's command (/usr/bin/mcp-server) is not on
          # McpSecurityService::ALLOWED_COMMANDS, so this must be blocked
          # before Open3.capture3 is ever reached (IMP-7046f6e448d6 review
          # item 2).
          expect(Open3).not_to receive(:capture3)
          expect(job).to receive(:log_error).with(/Tool discovery failed/, nil, hash_including(error: /Security error/))

          job.execute(server_id)
        end

        it 'spawns a whitelisted stdio command with a string-keyed sanitized env' do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => server_data.merge('command' => 'node') })

          expect(Open3).to receive(:capture3) do |env, command, *_args, **_opts|
            expect(command).to eq(['node', 'node'])
            expect(env.keys).to all(be_a(String))
            ['{}', '', instance_double(Process::Status, success?: true)]
          end

          job.execute(server_id)
        end

        it 'writes only the built JSON-RPC tools/list request to stdin, nothing else (IMP-97b6b1185748 item 5)' do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => server_data.merge('command' => 'node') })

          expect(Open3).to receive(:capture3) do |_env, _command, *_args, **opts|
            parsed = JSON.parse(opts[:stdin_data])
            expect(parsed).to eq('jsonrpc' => '2.0', 'id' => parsed['id'], 'method' => 'tools/list', 'params' => {})
            ['{}', '', instance_double(Process::Status, success?: true)]
          end

          job.execute(server_id)
        end
      end

      context 'http server' do
        let(:http_server_data) { server_data.merge('connection_type' => 'http', 'url' => 'http://localhost:3000') }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => http_server_data })
          allow(api_client).to receive(:post).and_return(success: true)
          stub_request(:post, 'http://localhost:3000/tools/list')
            .to_return(
              status: 200,
              body: { result: { tools: discovered_tools } }.to_json
            )
        end

        it 'discovers tools via HTTP' do
          job.execute(server_id)
        end
      end

      context 'websocket server' do
        let(:ws_server_data) { server_data.merge('connection_type' => 'websocket', 'url' => 'ws://localhost:3000') }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => ws_server_data })
        end

        it 'handles websocket discovery' do
          # Websocket discovery returns empty for now
          job.execute(server_id)
        end
      end

      context 'unknown connection type' do
        let(:unknown_server_data) { server_data.merge('connection_type' => 'grpc') }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => unknown_server_data })
        end

        it 'returns error for unknown type' do
          expect(job).to receive(:log_error).with(/Tool discovery failed/, anything, anything)

          job.execute(server_id)
        end
      end
    end
  end
end
