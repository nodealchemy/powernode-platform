# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::McpToolExecutions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mcp_server) { create(:mcp_server, account: account) }
  let(:mcp_tool) { create(:mcp_tool, mcp_server: mcp_server) }
  let(:mcp_tool_execution) { create(:mcp_tool_execution, mcp_tool: mcp_tool, user: user) }

  # Internal service authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/mcp_tool_executions/:id' do
    context 'with internal authentication' do
      it 'returns execution details' do
        get "/api/v1/internal/mcp_tool_executions/#{mcp_tool_execution.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response_data

        execution = data['mcp_tool_execution']
        expect(execution['id']).to eq(mcp_tool_execution.id)
        expect(execution['status']).to eq(mcp_tool_execution.status)
      end

      it 'includes tool and server information' do
        get "/api/v1/internal/mcp_tool_executions/#{mcp_tool_execution.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response_data

        execution = data['mcp_tool_execution']
        expect(execution['mcp_tool']).to be_present
        expect(execution['mcp_tool']['id']).to eq(mcp_tool.id)
        expect(execution['mcp_tool']['mcp_server']).to be_present
        expect(execution['mcp_tool']['mcp_server']['id']).to eq(mcp_server.id)
      end

      it 'includes execution parameters and result' do
        get "/api/v1/internal/mcp_tool_executions/#{mcp_tool_execution.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response_data

        execution = data['mcp_tool_execution']
        expect(execution).to have_key('parameters')
        expect(execution).to have_key('result')
        expect(execution).to have_key('error_message')
      end
    end

    context 'when execution does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/mcp_tool_executions/nonexistent-id',
            headers: internal_headers,
            as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/mcp_tool_executions/#{mcp_tool_execution.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/internal/mcp_tool_executions/:id' do
    context 'with internal authentication' do
      it 'starts execution when status is running' do
        execution = create(:mcp_tool_execution, mcp_tool: mcp_tool, user: user, status: 'pending')

        patch "/api/v1/internal/mcp_tool_executions/#{execution.id}",
              headers: internal_headers,
              params: { status: 'running' },
              as: :json

        expect_success_response
        data = json_response_data

        expect(data['mcp_tool_execution']['status']).to eq('running')
        expect(data['message']).to eq('Execution status updated successfully')

        execution.reload
        expect(execution.status).to eq('running')
        expect(execution.started_at).to be_within(1.second).of(Time.current)
      end

      it 'completes execution when status is completed' do
        execution = create(:mcp_tool_execution, mcp_tool: mcp_tool, user: user, status: 'running')
        result_data = { output: 'success', data: { value: 42 } }

        patch "/api/v1/internal/mcp_tool_executions/#{execution.id}",
              headers: internal_headers,
              params: { status: 'completed', result: result_data },
              as: :json

        expect_success_response
        data = json_response_data

        expect(data['mcp_tool_execution']['status']).to eq('completed')

        execution.reload
        expect(execution.status).to eq('completed')
        expect(execution.result).to eq(result_data.deep_stringify_keys)
        expect(execution.completed_at).to be_within(1.second).of(Time.current)
      end

      it 'fails execution when status is failed' do
        execution = create(:mcp_tool_execution, mcp_tool: mcp_tool, user: user, status: 'running')
        error_message = 'Tool execution failed due to timeout'

        patch "/api/v1/internal/mcp_tool_executions/#{execution.id}",
              headers: internal_headers,
              params: { status: 'failed', error: error_message },
              as: :json

        expect_success_response
        data = json_response_data

        expect(data['mcp_tool_execution']['status']).to eq('failed')

        execution.reload
        expect(execution.status).to eq('failed')
        expect(execution.error_message).to eq(error_message)
        expect(execution.completed_at).to be_within(1.second).of(Time.current)
      end

      it 'cancels execution when status is cancelled' do
        execution = create(:mcp_tool_execution, mcp_tool: mcp_tool, user: user, status: 'pending')

        patch "/api/v1/internal/mcp_tool_executions/#{execution.id}",
              headers: internal_headers,
              params: { status: 'cancelled' },
              as: :json

        expect_success_response
        data = json_response_data

        expect(data['mcp_tool_execution']['status']).to eq('cancelled')

        execution.reload
        expect(execution.status).to eq('cancelled')
      end

      it 'updates other execution attributes' do
        execution = create(:mcp_tool_execution, mcp_tool: mcp_tool, user: user, status: 'running')

        patch "/api/v1/internal/mcp_tool_executions/#{execution.id}",
              headers: internal_headers,
              params: { execution_time_ms: 1234 },
              as: :json

        expect_success_response

        execution.reload
        expect(execution.execution_time_ms).to eq(1234)
      end
    end

    context 'when execution does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/mcp_tool_executions/nonexistent-id',
              headers: internal_headers,
              params: { status: 'completed' },
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
