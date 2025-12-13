# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::McpServers', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :manager, account: account) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, :manager, account: other_account) }
  let(:limited_user) { create(:user, :member, account: account) }

  let(:headers) { auth_headers_for(user) }
  let(:other_headers) { auth_headers_for(other_user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  describe 'GET /api/v1/mcp_servers' do
    let!(:server1) { create(:mcp_server, :connected, account: account) }
    let!(:server2) { create(:mcp_server, :disconnected, account: account) }
    let!(:other_server) { create(:mcp_server, :connected, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of mcp servers for current account' do
        get '/api/v1/mcp_servers', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_servers']).to be_an(Array)
        expect(data['mcp_servers'].length).to eq(2)
        expect(data['mcp_servers'].none? { |s| s['id'] == other_server.id }).to be true
        expect(data['meta']).to include('total' => 2)
        expect(data['meta']).to have_key('connected_count')
        expect(data['meta']).to have_key('disconnected_count')
        expect(data['meta']).to have_key('error_count')
      end

      it 'filters by status' do
        get '/api/v1/mcp_servers', params: { status: 'connected' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['mcp_servers'].length).to eq(1)
        expect(data['mcp_servers'].first['status']).to eq('connected')
      end

      it 'filters by connection_type' do
        stdio_server = create(:mcp_server, :stdio, account: account)

        get '/api/v1/mcp_servers', params: { connection_type: 'stdio' }, headers: headers

        expect_success_response
        data = json_response_data
        # All servers created by default have stdio connection_type, so we expect 3 total
        # (server1, server2, and stdio_server all have connection_type: 'stdio')
        expect(data['mcp_servers'].all? { |s| s['connection_type'] == 'stdio' }).to be true
      end
    end

    context 'without mcp.servers.read permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        get '/api/v1/mcp_servers', headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to view MCP servers', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/mcp_servers', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/mcp_servers/:id' do
    let(:server) { create(:mcp_server, :connected, account: account) }
    let(:other_server) { create(:mcp_server, :connected, account: other_account) }

    before do
      create_list(:mcp_tool, 3, mcp_server: server)
    end

    context 'with proper permissions' do
      it 'returns mcp server details with tools' do
        get "/api/v1/mcp_servers/#{server.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_server']).to include(
          'id' => server.id,
          'name' => server.name,
          'status' => 'connected',
          'tools_count' => 3
        )
        expect(data['mcp_server']).to have_key('tools')
        expect(data['mcp_server']['tools']).to be_an(Array)
      end

      it 'returns not found for non-existent server' do
        get "/api/v1/mcp_servers/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('MCP server not found', 404)
      end
    end

    context 'accessing server from different account' do
      it 'returns not found error' do
        get "/api/v1/mcp_servers/#{other_server.id}", headers: headers, as: :json

        expect_error_response('MCP server not found', 404)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers' do
    let(:valid_params) do
      {
        mcp_server: {
          name: 'Test MCP Server',
          description: 'A test server',
          connection_type: 'stdio',
          command: 'npx',
          args: [ '-y', '@modelcontextprotocol/server-test' ],
          config: { timeout: 30 }
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new mcp server' do
        expect {
          post '/api/v1/mcp_servers', params: valid_params, headers: headers, as: :json
        }.to change { account.mcp_servers.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['mcp_server']).to include(
          'name' => 'Test MCP Server',
          'connection_type' => 'stdio',
          'status' => 'disconnected'
        )
        expect(data['message']).to eq('MCP server created successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = valid_params.deep_merge(mcp_server: { name: nil })

        post '/api/v1/mcp_servers', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without mcp.servers.write permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        post '/api/v1/mcp_servers', params: valid_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to manage MCP servers', 403)
      end
    end
  end

  describe 'PATCH /api/v1/mcp_servers/:id' do
    let(:server) { create(:mcp_server, :disconnected, account: account) }
    let(:update_params) do
      {
        mcp_server: {
          name: 'Updated Server Name',
          description: 'Updated description'
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the mcp server' do
        patch "/api/v1/mcp_servers/#{server.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_server']['name']).to eq('Updated Server Name')
        expect(data['mcp_server']['description']).to eq('Updated description')
        expect(data['message']).to eq('MCP server updated successfully')
      end

      it 'returns validation errors for invalid update' do
        invalid_params = { mcp_server: { connection_type: 'invalid' } }

        patch "/api/v1/mcp_servers/#{server.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without mcp.servers.write permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        patch "/api/v1/mcp_servers/#{server.id}", params: update_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to manage MCP servers', 403)
      end
    end
  end

  describe 'DELETE /api/v1/mcp_servers/:id' do
    let!(:server) { create(:mcp_server, :disconnected, account: account) }

    context 'with proper permissions' do
      it 'deletes the mcp server' do
        expect {
          delete "/api/v1/mcp_servers/#{server.id}", headers: headers, as: :json
        }.to change { account.mcp_servers.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('MCP server deleted successfully')
      end
    end

    context 'without mcp.servers.write permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        delete "/api/v1/mcp_servers/#{server.id}", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to manage MCP servers', 403)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:id/connect' do
    let(:server) { create(:mcp_server, :disconnected, account: account) }

    context 'with proper permissions' do
      it 'connects to the mcp server' do
        allow_any_instance_of(McpServer).to receive(:connect!).and_return(true)

        post "/api/v1/mcp_servers/#{server.id}/connect", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('MCP server connected successfully')
      end

      it 'returns error when connection fails' do
        allow_any_instance_of(McpServer).to receive(:connect!).and_raise(StandardError, 'Connection failed')

        post "/api/v1/mcp_servers/#{server.id}/connect", headers: headers, as: :json

        expect_error_response('Failed to connect: Connection failed', 422)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:id/disconnect' do
    let(:server) { create(:mcp_server, :connected, account: account) }

    context 'with proper permissions' do
      it 'disconnects from the mcp server' do
        allow_any_instance_of(McpServer).to receive(:disconnect!).and_return(true)

        post "/api/v1/mcp_servers/#{server.id}/disconnect", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('MCP server disconnected successfully')
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:id/health_check' do
    let(:server) { create(:mcp_server, :connected, account: account) }

    context 'with proper permissions' do
      it 'performs health check' do
        post "/api/v1/mcp_servers/#{server.id}/health_check", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_server_id']).to eq(server.id)
        expect(data['healthy']).to be true
        expect(data).to have_key('checked_at')
      end
    end

    context 'without mcp.servers.read permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        post "/api/v1/mcp_servers/#{server.id}/health_check", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to view MCP servers', 403)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:id/discover_tools' do
    let(:server) { create(:mcp_server, :connected, account: account) }

    context 'with proper permissions' do
      it 'discovers tools from the server' do
        tools = create_list(:mcp_tool, 3, mcp_server: server)
        allow_any_instance_of(McpServer).to receive(:discover_tools).and_return(tools)

        post "/api/v1/mcp_servers/#{server.id}/discover_tools", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_server_id']).to eq(server.id)
        expect(data['tools_discovered']).to eq(3)
        expect(data['tools']).to be_an(Array)
        expect(data['message']).to eq('Discovered 3 tools')
      end

      it 'returns error when discovery fails' do
        allow_any_instance_of(McpServer).to receive(:discover_tools).and_raise(StandardError, 'Discovery failed')

        post "/api/v1/mcp_servers/#{server.id}/discover_tools", headers: headers, as: :json

        expect_error_response('Failed to discover tools: Discovery failed', 422)
      end
    end

    context 'without mcp.servers.write permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        post "/api/v1/mcp_servers/#{server.id}/discover_tools", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to manage MCP servers', 403)
      end
    end
  end
end
