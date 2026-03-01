# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AguiController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:protocol_service) { instance_double(Ai::Agui::ProtocolService) }
  let(:agui_session) { create(:ai_agui_session, account: account, user: read_user) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    allow(Ai::Agui::ProtocolService).to receive(:new).and_return(protocol_service)
  end

  # ===========================================================================
  # AUTHENTICATION
  # ===========================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      get :sessions
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # GET #sessions
  # ===========================================================================

  describe 'GET #sessions' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns sessions list' do
        allow(protocol_service).to receive(:list_sessions).and_return([agui_session])

        get :sessions

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['sessions']).to be_an(Array)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :sessions
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #create_session
  # ===========================================================================

  describe 'POST #create_session' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'creates a new session' do
        allow(protocol_service).to receive(:create_session).and_return(agui_session)

        post :create_session, params: { agent_id: agent.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['session']).to be_a(Hash)
        expect(json_response['data']['session']['id']).to eq(agui_session.id)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :create_session, params: { agent_id: agent.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # GET #show_session
  # ===========================================================================

  describe 'GET #show_session' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns session details' do
        allow(protocol_service).to receive(:get_session).with(agui_session.id.to_s).and_return(agui_session)

        get :show_session, params: { id: agui_session.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['session']['id']).to eq(agui_session.id)
      end

      it 'returns not found for missing session' do
        allow(protocol_service).to receive(:get_session).and_raise(ActiveRecord::RecordNotFound)

        get :show_session, params: { id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :show_session, params: { id: agui_session.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # DELETE #destroy_session
  # ===========================================================================

  describe 'DELETE #destroy_session' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'destroys a session' do
        allow(protocol_service).to receive(:destroy_session).with(agui_session.id.to_s).and_return(true)

        delete :destroy_session, params: { id: agui_session.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['message']).to eq('Session destroyed')
      end

      it 'returns not found for missing session' do
        allow(protocol_service).to receive(:destroy_session).and_raise(ActiveRecord::RecordNotFound)

        delete :destroy_session, params: { id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        delete :destroy_session, params: { id: agui_session.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #push_state
  # ===========================================================================

  describe 'POST #push_state' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'pushes state delta' do
        allow(protocol_service).to receive(:get_session).with(agui_session.id.to_s).and_return(agui_session)

        state_sync_service = instance_double(Ai::Agui::StateSyncService)
        allow(Ai::Agui::StateSyncService).to receive(:new).and_return(state_sync_service)
        allow(state_sync_service).to receive(:push_state).and_return({
          sequence: 1,
          snapshot: { key: 'value' }
        })

        post :push_state, params: {
          id: agui_session.id,
          state_delta: [{ op: 'add', path: '/key', value: 'value' }]
        }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['sequence']).to eq(1)
      end

      it 'returns not found for missing session' do
        allow(protocol_service).to receive(:get_session).and_raise(ActiveRecord::RecordNotFound)

        post :push_state, params: {
          id: SecureRandom.uuid,
          state_delta: [{ op: 'add', path: '/key', value: 'value' }]
        }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :push_state, params: {
          id: agui_session.id,
          state_delta: []
        }
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

      it 'returns events list' do
        event = create(:ai_agui_event, :text_content, session: agui_session)
        allow(protocol_service).to receive(:get_events).and_return([event])

        get :events, params: { id: agui_session.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['events']).to be_an(Array)
      end

      it 'returns not found for missing session' do
        allow(protocol_service).to receive(:get_events).and_raise(ActiveRecord::RecordNotFound)

        get :events, params: { id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :events, params: { id: agui_session.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
