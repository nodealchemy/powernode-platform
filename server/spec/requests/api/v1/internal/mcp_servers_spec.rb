# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::McpServers', type: :request do
  let(:account) { create(:account) }
  let(:mcp_server) { create(:mcp_server, account: account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/mcp_servers' do
    context 'with internal authentication' do
      before do
        create_list(:mcp_server, 3, account: account)
      end

      it 'returns all MCP servers' do
        mcp_server # force creation of the let variable
        get '/api/v1/internal/mcp_servers', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data['mcp_servers']).to be_an(Array)
        expect(response_data['mcp_servers'].length).to eq(4) # 3 + initial server
      end

      it 'filters by status when provided' do
        connected_server = create(:mcp_server, account: account, status: 'connected')
        error_server = create(:mcp_server, account: account, status: 'error')

        get '/api/v1/internal/mcp_servers?status=connected', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response_data

        servers = response_data['mcp_servers']
        expect(servers.length).to be >= 1
        expect(servers.all? { |s| s['status'] == 'connected' }).to be true
      end

      it 'includes server attributes' do
        get '/api/v1/internal/mcp_servers', headers: internal_headers, as: :json

        response_data = json_response_data
        first_server = response_data['mcp_servers'].first

        expect(first_server).to include(
          'id', 'name', 'status', 'connection_type', 'account_id'
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/internal/mcp_servers', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/mcp_servers/:id' do
    context 'with internal authentication' do
      it 'returns MCP server details' do
        get "/api/v1/internal/mcp_servers/#{mcp_server.id}", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data['mcp_server']).to include(
          'id' => mcp_server.id,
          'name' => mcp_server.name,
          'status' => mcp_server.status
        )
      end

      it 'includes config when requested' do
        get "/api/v1/internal/mcp_servers/#{mcp_server.id}", headers: internal_headers, as: :json

        response_data = json_response_data
        server = response_data['mcp_server']

        expect(server).to have_key('env')
        expect(server).to have_key('config')
      end
    end

    context 'when server does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/mcp_servers/nonexistent-id', headers: internal_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PATCH /api/v1/internal/mcp_servers/:id' do
    context 'with internal authentication' do
      it 'updates MCP server status' do
        patch "/api/v1/internal/mcp_servers/#{mcp_server.id}",
              headers: internal_headers,
              params: { status: 'error', last_error: 'Connection failed' },
              as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data['mcp_server']['status']).to eq('error')
        expect(response_data['message']).to eq('MCP server updated successfully')

        mcp_server.reload
        expect(mcp_server.status).to eq('error')
        expect(mcp_server.last_error).to eq('Connection failed')
      end

      it 'updates last_health_check timestamp' do
        new_time = 1.hour.ago
        patch "/api/v1/internal/mcp_servers/#{mcp_server.id}",
              headers: internal_headers,
              params: { last_health_check: new_time },
              as: :json

        expect_success_response

        mcp_server.reload
        expect(mcp_server.last_health_check).to be_within(1.second).of(new_time)
      end
    end

    context 'when server does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/mcp_servers/nonexistent-id',
              headers: internal_headers,
              params: { status: 'active' },
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/internal/mcp_servers/:id/health_result' do
    context 'with internal authentication' do
      it 'updates health check result for healthy server' do
        post "/api/v1/internal/mcp_servers/#{mcp_server.id}/health_result",
             headers: internal_headers,
             params: { healthy: true, latency_ms: 45.5 },
             as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data['updated']).to be true
        expect(response_data['status']).to eq(mcp_server.reload.status)

        mcp_server.reload
        expect(mcp_server.capabilities['last_latency_ms']).to eq(45.5)
        expect(mcp_server.last_health_check).to be_within(1.second).of(Time.current)
      end

      it 'sets error status for unhealthy server' do
        current_status = mcp_server.status

        post "/api/v1/internal/mcp_servers/#{mcp_server.id}/health_result",
             headers: internal_headers,
             params: { healthy: false, latency_ms: nil },
             as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data['status']).to eq('error')
      end
    end

    context 'when server does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/mcp_servers/nonexistent-id/health_result',
             headers: internal_headers,
             params: { healthy: true },
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/internal/mcp_servers/:id/register_tools' do
    context 'with internal authentication' do
      it 'registers new tools for the server' do
        tools_data = [
          { name: 'tool1', description: 'First tool', input_schema: { type: 'object' }, enabled: true },
          { name: 'tool2', description: 'Second tool', input_schema: { type: 'object' }, enabled: false }
        ]

        post "/api/v1/internal/mcp_servers/#{mcp_server.id}/register_tools",
             headers: internal_headers,
             params: { tools: tools_data },
             as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data['tools_registered']).to eq(2)
        expect(response_data['total_tools']).to eq(2)

        expect(mcp_server.mcp_tools.count).to eq(2)
      end

      it 'updates existing tools' do
        existing_tool = create(:mcp_tool, mcp_server: mcp_server, name: 'existing_tool')

        tools_data = [
          { name: 'existing_tool', description: 'Updated description', input_schema: {} }
        ]

        post "/api/v1/internal/mcp_servers/#{mcp_server.id}/register_tools",
             headers: internal_headers,
             params: { tools: tools_data },
             as: :json

        expect_success_response

        existing_tool.reload
        expect(existing_tool.description).to eq('Updated description')
        expect(mcp_server.mcp_tools.count).to eq(1)
      end

      it 'sets default values for optional fields' do
        tools_data = [
          { name: 'minimal_tool', description: 'Minimal tool config' }
        ]

        post "/api/v1/internal/mcp_servers/#{mcp_server.id}/register_tools",
             headers: internal_headers,
             params: { tools: tools_data },
             as: :json

        expect_success_response

        tool = mcp_server.mcp_tools.find_by(name: 'minimal_tool')
        expect(tool.enabled).to be true
        expect(tool.permission_level).to eq('account')
        expect(tool.input_schema).to eq({})
      end
    end

    context 'when server does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/mcp_servers/nonexistent-id/register_tools',
             headers: internal_headers,
             params: { tools: [] },
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
