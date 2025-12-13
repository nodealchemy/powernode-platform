# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::McpTools', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :manager, account: account) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, :manager, account: other_account) }
  let(:limited_user) { create(:user, :member, account: account) }

  let(:headers) { auth_headers_for(user) }
  let(:other_headers) { auth_headers_for(other_user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  let(:server) { create(:mcp_server, :connected, account: account) }
  let(:other_server) { create(:mcp_server, :connected, account: other_account) }

  describe 'GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools' do
    before do
      create_list(:mcp_tool, 3, :enabled, mcp_server: server)
      create_list(:mcp_tool, 2, :disabled, mcp_server: server)
      create_list(:mcp_tool, 2, mcp_server: other_server)
    end

    context 'with proper permissions' do
      it 'returns list of tools for the server' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_tools']).to be_an(Array)
        expect(data['mcp_tools'].length).to eq(5)
        expect(data['mcp_server']).to include(
          'id' => server.id,
          'name' => server.name
        )
        expect(data['meta']).to include(
          'total' => 5,
          'enabled_count' => 3,
          'disabled_count' => 2
        )
      end

      it 'filters by enabled status' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools",
            params: { enabled: true },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['mcp_tools'].length).to eq(3)
        expect(data['mcp_tools'].all? { |t| t['enabled'] }).to be true
      end
    end

    context 'accessing server from different account' do
      it 'returns not found error' do
        get "/api/v1/mcp_servers/#{other_server.id}/mcp_tools", headers: headers, as: :json

        expect_error_response('MCP server not found', 404)
      end
    end

    context 'without mcp.tools.read permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to view MCP tools', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:id' do
    let(:tool) { create(:mcp_tool, :enabled, mcp_server: server) }

    context 'with proper permissions' do
      it 'returns tool details' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_tool']).to include(
          'id' => tool.id,
          'name' => tool.name,
          'enabled' => true
        )
        expect(data['mcp_tool']).to have_key('input_schema')
        expect(data['mcp_tool']).to have_key('output_schema')
        expect(data['mcp_tool']).to have_key('config')
        expect(data['mcp_server']).to include('id' => server.id)
      end

      it 'returns not found for non-existent tool' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('MCP tool not found', 404)
      end
    end

    context 'accessing server from different account' do
      it 'returns not found error' do
        get "/api/v1/mcp_servers/#{other_server.id}/mcp_tools/#{tool.id}", headers: headers, as: :json

        expect_error_response('MCP server not found', 404)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:id/execute' do
    let(:tool) { create(:mcp_tool, :enabled, mcp_server: server) }
    let(:execution_params) do
      {
        parameters: {
          query: 'test query',
          limit: 10
        }
      }
    end

    context 'with proper permissions' do
      context 'with enabled tool and connected server' do
        it 'executes the tool' do
          execution = create(:mcp_tool_execution, :pending, mcp_tool: tool, user: user)
          allow_any_instance_of(McpTool).to receive(:validate_parameters).and_return({ valid: true })
          allow_any_instance_of(McpTool).to receive(:execute).and_return(execution)

          post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/execute",
               params: execution_params,
               headers: headers,
               as: :json

          expect(response).to have_http_status(:accepted)
          data = json_response_data
          expect(data['execution']).to include(
            'id' => execution.id,
            'status' => 'pending'
          )
          expect(data['message']).to eq('Tool execution started')
        end
      end

      context 'with disabled tool' do
        let(:disabled_tool) { create(:mcp_tool, :disabled, mcp_server: server) }

        it 'returns error for disabled tool' do
          post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{disabled_tool.id}/execute",
               params: execution_params,
               headers: headers,
               as: :json

          expect_error_response('Tool is disabled', 422)
        end
      end

      context 'with disconnected server' do
        let(:disconnected_server) { create(:mcp_server, :disconnected, account: account) }
        let(:disconnected_tool) { create(:mcp_tool, :enabled, mcp_server: disconnected_server) }

        it 'returns error for disconnected server' do
          post "/api/v1/mcp_servers/#{disconnected_server.id}/mcp_tools/#{disconnected_tool.id}/execute",
               params: execution_params,
               headers: headers,
               as: :json

          expect_error_response('MCP server is not connected', 422)
        end
      end

      context 'with invalid parameters' do
        it 'returns validation error' do
          allow_any_instance_of(McpTool).to receive(:validate_parameters).and_return({
            valid: false,
            errors: [ 'query is required', 'limit must be positive' ]
          })

          post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/execute",
               params: { parameters: {} },
               headers: headers,
               as: :json

          expect_error_response('Invalid parameters: query is required, limit must be positive', 422)
        end
      end
    end

    context 'without mcp.tools.execute permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/execute",
             params: execution_params,
             headers: limited_headers,
             as: :json

        expect_error_response('Insufficient permissions to execute MCP tools', 403)
      end
    end
  end

  describe 'GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:id/stats' do
    let(:tool) { create(:mcp_tool, :enabled, mcp_server: server) }

    before do
      create_list(:mcp_tool_execution, 5, :success, mcp_tool: tool, user: user, duration_ms: 100)
      create_list(:mcp_tool_execution, 2, :failed, mcp_tool: tool, user: user, duration_ms: 200)
      create_list(:mcp_tool_execution, 1, :pending, mcp_tool: tool, user: user)
      create_list(:mcp_tool_execution, 1, :running, mcp_tool: tool, user: user)
    end

    context 'with proper permissions' do
      it 'returns tool statistics' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/stats", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mcp_tool_id']).to eq(tool.id)
        expect(data['stats']).to include(
          'total_executions' => 9,
          'success_count' => 5,
          'failure_count' => 2,
          'pending_count' => 1,
          'running_count' => 1
        )
        expect(data['stats']).to have_key('success_rate')
        expect(data['stats']).to have_key('average_duration_ms')
        expect(data['stats']).to have_key('recent_30_days')
        expect(data['stats']).to have_key('last_execution_at')
        expect(data['stats']).to have_key('first_execution_at')
        expect(data['stats']['success_rate']).to be_within(0.1).of(55.56)
      end
    end

    context 'without mcp.tools.read permission' do
      # Member role doesn't have MCP permissions
      it 'returns forbidden error' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/stats", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to view MCP tools', 403)
      end
    end
  end
end
