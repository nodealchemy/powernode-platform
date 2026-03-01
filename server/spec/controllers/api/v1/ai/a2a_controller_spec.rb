# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::A2aController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:execute_user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.execute']) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:protocol_service) { instance_double(Ai::A2a::ProtocolService) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    allow(Ai::A2a::ProtocolService).to receive(:new).and_return(protocol_service)
  end

  # ===========================================================================
  # AUTHENTICATION
  # ===========================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      get :discover
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # POST #discover
  # ===========================================================================

  describe 'POST #discover' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns discovered agents on success' do
        allow(protocol_service).to receive(:discover_agents).and_return({
          success: true,
          agents: [{ id: agent.id, name: agent.name }],
          total: 1
        })

        post :discover, params: { task_description: 'code review', visibility: 'internal' }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['agents']).to be_an(Array)
        expect(json_response['data']['total']).to eq(1)
      end

      it 'returns error on failure' do
        allow(protocol_service).to receive(:discover_agents).and_return({
          success: false,
          error: 'Discovery failed'
        })

        post :discover, params: { task_description: 'test' }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :discover, params: { task_description: 'test' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #jsonrpc
  # ===========================================================================

  describe 'POST #jsonrpc' do
    context 'with ai.agents.execute permission' do
      before { sign_in execute_user }

      it 'returns JSON-RPC response' do
        allow(protocol_service).to receive(:handle_jsonrpc).and_return({
          jsonrpc: '2.0',
          id: '1',
          result: { status: 'ok' }
        })

        post :jsonrpc, params: { jsonrpc: '2.0', method: 'tasks/send', id: '1' }

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body['jsonrpc']).to eq('2.0')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :jsonrpc, params: { jsonrpc: '2.0', method: 'tasks/send', id: '1' }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in read_user }

      it 'returns forbidden for execute action' do
        post :jsonrpc, params: { jsonrpc: '2.0', method: 'tasks/send', id: '1' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # GET #show_task
  # ===========================================================================

  describe 'GET #show_task' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns task on success' do
        allow(protocol_service).to receive(:get_task).and_return({
          success: true,
          task: { id: 'task-123', status: 'completed' }
        })

        get :show_task, params: { id: 'task-123' }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns not found for missing task' do
        allow(protocol_service).to receive(:get_task).and_return({
          success: false,
          error: 'Task not found'
        })

        get :show_task, params: { id: 'nonexistent' }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :show_task, params: { id: 'task-123' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #cancel_task
  # ===========================================================================

  describe 'POST #cancel_task' do
    context 'with ai.agents.execute permission' do
      before { sign_in execute_user }

      it 'cancels task on success' do
        allow(protocol_service).to receive(:cancel_task).and_return({
          success: true,
          task: { id: 'task-123', status: 'cancelled' }
        })

        post :cancel_task, params: { id: 'task-123', reason: 'No longer needed' }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns error on failure' do
        allow(protocol_service).to receive(:cancel_task).and_return({
          success: false,
          error: 'Cannot cancel completed task'
        })

        post :cancel_task, params: { id: 'task-123' }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :cancel_task, params: { id: 'task-123' }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in read_user }

      it 'returns forbidden for execute action' do
        post :cancel_task, params: { id: 'task-123' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
