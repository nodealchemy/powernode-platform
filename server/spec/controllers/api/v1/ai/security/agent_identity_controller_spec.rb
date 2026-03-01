# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::Security::AgentIdentityController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:security_user) { create(:user, account: account, permissions: ['ai.security.manage']) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:identity_service) { instance_double(Ai::Security::AgentIdentityService) }

  let!(:identity) do
    create(:ai_agent_identity, account: account, agent_id: agent.id)
  end

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    allow(Ai::Security::AgentIdentityService).to receive(:new).and_return(identity_service)
  end

  # ===========================================================================
  # AUTHENTICATION
  # ===========================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      get :index
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # GET #index
  # ===========================================================================

  describe 'GET #index' do
    context 'with ai.security.manage permission' do
      before { sign_in security_user }

      it 'returns identities list' do
        get :index

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['items']).to be_an(Array)
        expect(json_response['data']['items'].length).to eq(1)
        expect(json_response['data']['pagination']).to include('current_page', 'per_page', 'total_count')
      end

      it 'filters by agent_id' do
        other_agent = create(:ai_agent, account: account)
        create(:ai_agent_identity, account: account, agent_id: other_agent.id)

        get :index, params: { agent_id: agent.id }

        expect(response).to have_http_status(:success)
        items = json_response['data']['items']
        items.each do |item|
          expect(item['agent_id']).to eq(agent.id)
        end
      end

      it 'filters by status' do
        create(:ai_agent_identity, :revoked, account: account, agent_id: agent.id)

        get :index, params: { status: 'active' }

        expect(response).to have_http_status(:success)
        items = json_response['data']['items']
        items.each do |item|
          expect(item['status']).to eq('active')
        end
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :index
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # GET #show
  # ===========================================================================

  describe 'GET #show' do
    context 'with ai.security.manage permission' do
      before { sign_in security_user }

      it 'returns identity details' do
        get :show, params: { id: identity.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['id']).to eq(identity.id)
        expect(json_response['data']).to include(
          'agent_id', 'key_fingerprint', 'algorithm', 'status', 'agent_uri'
        )
      end

      it 'returns not found for missing identity' do
        get :show, params: { id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :show, params: { id: identity.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #provision
  # ===========================================================================

  describe 'POST #provision' do
    context 'with ai.security.manage permission' do
      before { sign_in security_user }

      it 'provisions a new identity' do
        new_identity = create(:ai_agent_identity, account: account, agent_id: agent.id)
        allow(identity_service).to receive(:provision!).and_return(new_identity)

        post :provision, params: { agent_id: agent.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['agent_id']).to eq(agent.id)
      end

      it 'returns not found for missing agent' do
        post :provision, params: { agent_id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end

      it 'returns error on service failure' do
        allow(identity_service).to receive(:provision!).and_raise(
          Ai::Security::AgentIdentityService::IdentityError, 'Identity already exists'
        )

        post :provision, params: { agent_id: agent.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :provision, params: { agent_id: agent.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #rotate
  # ===========================================================================

  describe 'POST #rotate' do
    context 'with ai.security.manage permission' do
      before { sign_in security_user }

      it 'rotates an identity' do
        new_identity = create(:ai_agent_identity, account: account, agent_id: agent.id)
        allow(identity_service).to receive(:rotate!).and_return(new_identity)

        post :rotate, params: { id: identity.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns not found for missing identity' do
        post :rotate, params: { id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end

      it 'returns error on service failure' do
        allow(identity_service).to receive(:rotate!).and_raise(
          Ai::Security::AgentIdentityService::IdentityError, 'Cannot rotate revoked identity'
        )

        post :rotate, params: { id: identity.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :rotate, params: { id: identity.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #revoke
  # ===========================================================================

  describe 'POST #revoke' do
    context 'with ai.security.manage permission' do
      before { sign_in security_user }

      it 'revokes an identity' do
        allow(identity_service).to receive(:revoke!).and_return({ revoked: true })

        post :revoke, params: { id: identity.id, reason: 'Compromised key' }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
      end

      it 'returns not found for missing identity' do
        post :revoke, params: { id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end

      it 'returns error on service failure' do
        allow(identity_service).to receive(:revoke!).and_raise(
          Ai::Security::AgentIdentityService::IdentityError, 'Already revoked'
        )

        post :revoke, params: { id: identity.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :revoke, params: { id: identity.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #verify
  # ===========================================================================

  describe 'POST #verify' do
    context 'with ai.security.manage permission' do
      before { sign_in security_user }

      it 'verifies a signature' do
        allow(identity_service).to receive(:verify).and_return({
          valid: true, agent_id: agent.id
        })

        post :verify, params: {
          agent_id: agent.id,
          payload: 'test data',
          signature: 'base64signature'
        }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['valid']).to be true
      end

      it 'returns error on verification failure' do
        allow(identity_service).to receive(:verify).and_raise(
          Ai::Security::AgentIdentityService::VerificationError, 'Invalid signature'
        )

        post :verify, params: {
          agent_id: agent.id,
          payload: 'test',
          signature: 'invalid'
        }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :verify, params: {
          agent_id: agent.id,
          payload: 'test',
          signature: 'sig'
        }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
