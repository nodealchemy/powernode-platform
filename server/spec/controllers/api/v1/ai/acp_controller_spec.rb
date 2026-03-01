# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AcpController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:execute_user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.execute']) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:acp_service) { instance_double(Ai::Acp::ProtocolService) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    allow(Ai::Acp::ProtocolService).to receive(:new).and_return(acp_service)
  end

  # ===========================================================================
  # AUTHENTICATION
  # ===========================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      get :info
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # GET #info
  # ===========================================================================

  describe 'GET #info' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns protocol information' do
        allow(acp_service).to receive(:protocol_info).and_return({
          success: true,
          protocol: 'ACP',
          version: '1.0'
        })

        get :info

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['protocol']).to eq('ACP')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :info
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # GET #list_agents
  # ===========================================================================

  describe 'GET #list_agents' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns agents list on success' do
        allow(acp_service).to receive(:list_agents).and_return({
          success: true,
          agents: [{ id: agent.id, name: agent.name }],
          total: 1
        })

        get :list_agents

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['agents']).to be_an(Array)
      end

      it 'returns error on failure' do
        allow(acp_service).to receive(:list_agents).and_return({
          success: false,
          error: 'Failed to list agents'
        })

        get :list_agents

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :list_agents
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # GET #show_agent
  # ===========================================================================

  describe 'GET #show_agent' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns agent profile on success' do
        allow(acp_service).to receive(:get_agent_profile).and_return({
          success: true,
          agent: { id: agent.id, name: agent.name, capabilities: [] }
        })

        get :show_agent, params: { id: agent.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns not found for invalid agent' do
        allow(acp_service).to receive(:get_agent_profile).and_return({
          success: false,
          error: 'Agent not found',
          http_status: :not_found
        })

        get :show_agent, params: { id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :show_agent, params: { id: agent.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #negotiate
  # ===========================================================================

  describe 'POST #negotiate' do
    context 'with ai.agents.execute permission' do
      before { sign_in execute_user }

      it 'returns negotiation result on success' do
        allow(acp_service).to receive(:negotiate_capabilities).and_return({
          success: true,
          agreement: { accepted: true }
        })

        post :negotiate, params: {
          id: agent.id,
          offered_capabilities: ['text_generation'],
          required_capabilities: ['conversation']
        }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns error on failure' do
        allow(acp_service).to receive(:negotiate_capabilities).and_return({
          success: false,
          error: 'Negotiation failed'
        })

        post :negotiate, params: { id: agent.id }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :negotiate, params: { id: agent.id }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in read_user }

      it 'returns forbidden' do
        post :negotiate, params: { id: agent.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #send_message
  # ===========================================================================

  describe 'POST #send_message' do
    context 'with ai.agents.execute permission' do
      before { sign_in execute_user }

      it 'sends message on success' do
        allow(acp_service).to receive(:send_message).and_return({
          success: true,
          message_id: 'msg-123',
          status: 'delivered'
        })

        post :send_message, params: {
          id: agent.id,
          from_agent_id: SecureRandom.uuid,
          message: { type: 'text', content: 'Hello agent' }
        }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns error on failure' do
        allow(acp_service).to receive(:send_message).and_return({
          success: false,
          error: 'Agent unavailable'
        })

        post :send_message, params: {
          id: agent.id,
          message: { type: 'text', content: 'test' }
        }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :send_message, params: {
          id: agent.id,
          message: { type: 'text', content: 'test' }
        }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # GET #show_message
  # ===========================================================================

  describe 'GET #show_message' do
    context 'with ai.agents.execute permission' do
      before { sign_in execute_user }

      it 'returns message on success' do
        allow(acp_service).to receive(:get_message).and_return({
          success: true,
          message: { id: 'msg-123', status: 'delivered' }
        })

        get :show_message, params: { id: 'msg-123' }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns not found for missing message' do
        allow(acp_service).to receive(:get_message).and_return({
          success: false,
          error: 'Message not found'
        })

        get :show_message, params: { id: 'nonexistent' }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :show_message, params: { id: 'msg-123' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #cancel_message
  # ===========================================================================

  describe 'POST #cancel_message' do
    context 'with ai.agents.execute permission' do
      before { sign_in execute_user }

      it 'cancels message on success' do
        allow(acp_service).to receive(:cancel_message).and_return({
          success: true,
          status: 'cancelled'
        })

        post :cancel_message, params: { id: 'msg-123', reason: 'No longer needed' }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns error on failure' do
        allow(acp_service).to receive(:cancel_message).and_return({
          success: false,
          error: 'Cannot cancel'
        })

        post :cancel_message, params: { id: 'msg-123' }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :cancel_message, params: { id: 'msg-123' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # GET #events
  # ===========================================================================

  describe 'GET #events' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns events on success' do
        allow(acp_service).to receive(:get_agent_events).and_return({
          success: true,
          events: [{ type: 'message_received', timestamp: Time.current.iso8601 }],
          total: 1
        })

        get :events, params: { id: agent.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns error on failure' do
        allow(acp_service).to receive(:get_agent_events).and_return({
          success: false,
          error: 'Events not available'
        })

        get :events, params: { id: agent.id }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :events, params: { id: agent.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
