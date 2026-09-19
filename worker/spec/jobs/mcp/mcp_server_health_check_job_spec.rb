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
      'id' => server_id,
      'name' => 'Test MCP Server',
      'connection_type' => 'stdio',
      'command' => '/usr/bin/mcp-server',
      'args' => [],
      'env' => {},
      'status' => 'connected'
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

    context 'when checking all servers' do
      let(:servers) do
        [
          { 'id' => 'server-1', 'name' => 'Server 1', 'status' => 'connected' },
          { 'id' => 'server-2', 'name' => 'Server 2', 'status' => 'connected' }
        ]
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/mcp_servers?status=connected')
          .and_return('success' => true, 'data' => { 'mcp_servers' => servers })
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
          .and_return('success' => true, 'data' => { 'mcp_servers' => [] })
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
          .and_return('success' => true, 'data' => { 'mcp_server' => server_data })
        allow(api_client).to receive(:post).and_return('success' => true)
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
        let(:disconnected_server) { server_data.merge('status' => 'disconnected') }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => disconnected_server })
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
          .and_return('success' => false, 'error' => 'Not found')
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
            .and_return('success' => true, 'data' => { 'mcp_server' => server_data })
          allow(api_client).to receive(:post).and_return('success' => true)
        end

        it 'pings stdio server' do
          expect(job).to receive(:ping_server).and_call_original

          job.execute(server_id)
        end

        it 'refuses a non-whitelisted stdio command via the real McpSecurityService' do
          # server_data's command (/usr/bin/mcp-server) is not on
          # McpSecurityService::ALLOWED_COMMANDS, so this must be blocked
          # before McpSecurityService.spawn_stdio is ever reached
          # (IMP-7046f6e448d6 review item 2).
          expect(McpSecurityService).not_to receive(:spawn_stdio)

          job.execute(server_id)

          expect(api_client).to have_received(:post)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}/health_result",
              hash_including(healthy: false)
            )
        end

        # IMP-4689ce5a4acb: these mock .spawn_stdio itself, not the Open3
        # call inside it — that internal contract (Open3.popen3/
        # unsetenv_others/pgroup) is exercised for real by
        # mcp_security_service_spec.rb's real-spawn specs.
        it 'spawns a whitelisted stdio command with a string-keyed sanitized env' do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => server_data.merge('command' => 'node') })

          expect(McpSecurityService).to receive(:spawn_stdio) do |command, env, *_rest, **_kwargs|
            expect(command).to eq('node')
            expect(env.keys).to all(be_a(String))
            ['{}', '', instance_double(Process::Status, success?: true)]
          end

          job.execute(server_id)
        end

        # IMP-a50680fd53d8 — admin-gated, same trust tier and gating as
        # allow_extended_commands (carried by the IMP-427e98cae0be
        # capabilities serialization allowlist).
        it "passes allow_network: true through to spawn_stdio when the server's capabilities say so" do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => server_data.merge(
              'command' => 'node', 'capabilities' => { 'allow_network' => true }
            ) })

          expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, allow_network:, **_kwargs|
            expect(allow_network).to be true
            ['{}', '', instance_double(Process::Status, success?: true)]
          end

          job.execute(server_id)

          # Asserting the actual outcome, not just assertions inside the
          # mock block, matters here: ping_stdio_server wraps the
          # spawn_stdio call in its own `rescue StandardError => e`, so if
          # the real call omits the allow_network: keyword the block
          # requires, the resulting ArgumentError is swallowed into a
          # {healthy: false, error: ...} result rather than surfacing as a
          # spec failure — a test with no post-call assertion would pass
          # either way.
          expect(api_client).to have_received(:post)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}/health_result",
              hash_including(healthy: true)
            )
        end

        # IMP-bf72723ef161 — same reasoning as allow_network above.
        it "passes egress_allowlist through to spawn_stdio when the server's capabilities carry one" do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => server_data.merge(
              'command' => 'node', 'capabilities' => { 'egress_allowlist' => [ '10.0.0.0/8' ] }
            ) })

          expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, egress_allowlist:, **_kwargs|
            expect(egress_allowlist).to eq([ '10.0.0.0/8' ])
            ['{}', '', instance_double(Process::Status, success?: true)]
          end

          job.execute(server_id)

          expect(api_client).to have_received(:post)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}/health_result",
              hash_including(healthy: true)
            )
        end

        it 'writes only the built JSON-RPC ping request to stdin, nothing else (IMP-97b6b1185748 item 5)' do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => server_data.merge('command' => 'node') })

          expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, **_kwargs|
            parsed = JSON.parse(stdin_data)
            expect(parsed).to eq('jsonrpc' => '2.0', 'id' => parsed['id'], 'method' => 'ping', 'params' => {})
            ['{}', '', instance_double(Process::Status, success?: true)]
          end

          job.execute(server_id)
        end

        # IMP-4689ce5a4acb: spawn_stdio now raises StdioTimeoutError (a
        # SecurityError, hence StandardError, subclass) on a deadline
        # expiry instead of hanging forever. #ping_stdio_server's OWN
        # `rescue StandardError => e` around this call already maps it
        # into this method's existing error shape — no code change
        # needed, only this spec proving it.
        it "maps a stdio deadline expiry into this job's existing error shape" do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => server_data.merge('command' => 'node') })
          allow(McpSecurityService).to receive(:spawn_stdio)
            .and_raise(McpSecurityService::StdioTimeoutError, "stdio MCP server 'node' exceeded 30s and was killed")
          expect(job).to receive(:log_warn).with(/health check failed/, hash_including(error: /exceeded 30s/))

          job.execute(server_id)

          expect(api_client).to have_received(:post)
            .with(
              "/api/v1/internal/mcp_servers/#{server_id}/health_result",
              hash_including(healthy: false)
            )
        end
      end

      context 'http server' do
        let(:http_server_data) { server_data.merge('connection_type' => 'http', 'url' => 'http://localhost:3000') }

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/mcp_servers/#{server_id}")
            .and_return('success' => true, 'data' => { 'mcp_server' => http_server_data })
          allow(api_client).to receive(:post).and_return('success' => true)
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
