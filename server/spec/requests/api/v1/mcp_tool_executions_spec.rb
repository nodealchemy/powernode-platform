# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::McpToolExecutions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :manager, account: account) }
  let(:admin_user) { create(:user, :owner, account: account) }
  let(:other_user) { create(:user, :manager, account: account) }
  let(:limited_user) { create(:user, :member, account: account) }

  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:other_headers) { auth_headers_for(other_user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  let(:server) { create(:mcp_server, :connected, account: account) }
  let(:tool) { create(:mcp_tool, :enabled, mcp_server: server) }

  describe 'GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:mcp_tool_id/executions' do
    before do
      create_list(:mcp_tool_execution, 3, :success, mcp_tool: tool, user: user)
      create_list(:mcp_tool_execution, 2, :failed, mcp_tool: tool, user: user)
      create_list(:mcp_tool_execution, 2, :pending, mcp_tool: tool, user: other_user)
    end

    context 'with proper permissions as regular user' do
      it 'returns only own executions' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response
        expect(data['executions']).to be_an(Array)
        expect(data['executions'].length).to eq(5) # Only user's executions
        expect(data['executions'].all? { |e| e['user_id'] == user.id }).to be true
        expect(data['meta']).to have_key('pending_count')
        expect(data['meta']).to have_key('running_count')
        expect(data['meta']).to have_key('success_count')
        expect(data['meta']).to have_key('failed_count')
        expect(data['meta']).to have_key('cancelled_count')
      end

      it 'filters by status' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions",
            params: { status: 'success' },
            headers: headers,
            as: :json

        expect_success_response
        data = json_response
        expect(data['executions'].length).to eq(3)
        expect(data['executions'].all? { |e| e['status'] == 'success' }).to be true
      end

      it 'filters by time' do
        old_execution = create(:mcp_tool_execution, :success, mcp_tool: tool, user: user)
        old_execution.update_column(:created_at, 2.days.ago)

        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions",
            params: { since: 1.day.ago.iso8601 },
            headers: headers,
            as: :json

        expect_success_response
        data = json_response
        expect(data['executions'].none? { |e| e['id'] == old_execution.id }).to be true
      end

      it 'supports pagination' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions",
            params: { page: 1, per_page: 2 },
            headers: headers,
            as: :json

        expect_success_response
        data = json_response
        expect(data['executions'].length).to eq(2)
        expect(data['pagination']).to include(
          'page' => 1,
          'per_page' => 2,
          'total' => 5,
          'pages' => 3
        )
      end
    end

    context 'with admin permissions' do
      it 'returns all executions including other users' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions",
            headers: admin_headers,
            as: :json

        expect_success_response
        data = json_response
        expect(data['executions'].length).to eq(7) # All executions
      end

      it 'filters by user_id when admin' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions",
            params: { user_id: user.id },
            headers: admin_headers,
            as: :json

        expect_success_response
        data = json_response
        expect(data['executions'].length).to eq(5)
        expect(data['executions'].all? { |e| e['user_id'] == user.id }).to be true
      end
    end

    context 'without mcp.executions.read permission' do
      before do
        limited_user.permissions.delete('mcp.executions.read')
        limited_user.save!
      end

      it 'returns forbidden error' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions",
            headers: limited_headers,
            as: :json

        expect_error_response('Insufficient permissions to view MCP tool executions', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:mcp_tool_id/executions/:id' do
    let(:execution) { create(:mcp_tool_execution, :success, mcp_tool: tool, user: user) }
    let(:other_execution) { create(:mcp_tool_execution, :success, mcp_tool: tool, user: other_user) }

    context 'with proper permissions' do
      it 'returns own execution details' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{execution.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response
        expect(data['execution']).to include(
          'id' => execution.id,
          'status' => 'success',
          'user_id' => user.id
        )
        expect(data['execution']).to have_key('parameters')
        expect(data['execution']).to have_key('result')
        expect(data['execution']).to have_key('error_message')
        expect(data['execution']).to have_key('metadata')
        expect(data['mcp_tool']).to include('id' => tool.id)
        expect(data['mcp_server']).to include('id' => server.id)
      end

      it 'returns forbidden for other user execution' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{other_execution.id}",
            headers: headers,
            as: :json

        expect_error_response('Insufficient permissions to view this execution', 403)
      end

      it 'returns not found for non-existent execution' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{SecureRandom.uuid}",
            headers: headers,
            as: :json

        expect_error_response('Tool execution not found', 404)
      end
    end

    context 'with admin permissions' do
      it 'can view any user execution' do
        get "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{other_execution.id}",
            headers: admin_headers,
            as: :json

        expect_success_response
        data = json_response
        expect(data['execution']['id']).to eq(other_execution.id)
      end
    end
  end

  describe 'POST /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:mcp_tool_id/executions/:id/cancel' do
    context 'with proper permissions' do
      context 'cancelling own execution' do
        let(:pending_execution) { create(:mcp_tool_execution, :pending, mcp_tool: tool, user: user) }
        let(:running_execution) { create(:mcp_tool_execution, :running, mcp_tool: tool, user: user) }
        let(:completed_execution) { create(:mcp_tool_execution, :success, mcp_tool: tool, user: user) }

        it 'cancels pending execution' do
          allow_any_instance_of(McpToolExecution).to receive(:cancel!).and_return(true)

          post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{pending_execution.id}/cancel",
               headers: headers,
               as: :json

          expect_success_response
          data = json_response
          expect(data['message']).to eq('Execution cancelled successfully')
        end

        it 'cancels running execution' do
          allow_any_instance_of(McpToolExecution).to receive(:cancel!).and_return(true)

          post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{running_execution.id}/cancel",
               headers: headers,
               as: :json

          expect_success_response
        end

        it 'returns error for completed execution' do
          post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{completed_execution.id}/cancel",
               headers: headers,
               as: :json

          expect_error_response("Cannot cancel execution with status 'success'", 422)
        end
      end

      context 'cancelling other user execution' do
        let(:other_execution) { create(:mcp_tool_execution, :pending, mcp_tool: tool, user: other_user) }

        it 'returns forbidden for regular user' do
          post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{other_execution.id}/cancel",
               headers: headers,
               as: :json

          expect_error_response('Insufficient permissions to cancel this execution', 403)
        end

        it 'allows admin to cancel' do
          allow_any_instance_of(McpToolExecution).to receive(:cancel!).and_return(true)

          post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{other_execution.id}/cancel",
               headers: admin_headers,
               as: :json

          expect_success_response
        end
      end
    end

    context 'without mcp.executions.write permission' do
      let(:execution) { create(:mcp_tool_execution, :pending, mcp_tool: tool, user: limited_user) }

      before do
        limited_user.permissions.delete('mcp.executions.write')
        limited_user.save!
      end

      it 'returns forbidden error' do
        post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{execution.id}/cancel",
             headers: limited_headers,
             as: :json

        expect_error_response('Insufficient permissions to manage MCP tool executions', 403)
      end
    end

    context 'when cancel fails' do
      let(:execution) { create(:mcp_tool_execution, :pending, mcp_tool: tool, user: user) }

      it 'returns error message' do
        allow_any_instance_of(McpToolExecution).to receive(:cancel!).and_raise(StandardError, 'Cancellation failed')

        post "/api/v1/mcp_servers/#{server.id}/mcp_tools/#{tool.id}/executions/#{execution.id}/cancel",
             headers: headers,
             as: :json

        expect_error_response('Failed to cancel execution: Cancellation failed', 500)
      end
    end
  end
end
