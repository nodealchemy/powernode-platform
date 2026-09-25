# frozen_string_literal: true

require 'rails_helper'

# Tests for the Security namespace controllers:
# - QuarantineController
# - AgentIdentityController

RSpec.describe 'Api::V1::Ai::Security', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.security.manage']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }
  let(:agent) { create(:ai_agent, account: account, creator: user) }

  # ============================================================================
  # QUARANTINE
  # ============================================================================

  describe 'QuarantineController' do
    let(:quarantine_service) { instance_double(Ai::Security::QuarantineService) }
    let!(:quarantine_record) { create(:ai_quarantine_record, account: account, agent_id: agent.id) }

    before do
      allow(Ai::Security::QuarantineService).to receive(:new).and_return(quarantine_service)
    end

    describe 'authentication' do
      it 'returns 401 without token' do
        get '/api/v1/ai/security/quarantine',
          headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe 'authorization' do
      it 'returns 403 without permission' do
        get '/api/v1/ai/security/quarantine',
          headers: auth_headers_for(no_perms_user)
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'GET /api/v1/ai/security/quarantine' do
      it 'returns quarantine records' do
        get '/api/v1/ai/security/quarantine',
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(json_response['data']['items']).to be_an(Array)
      end
    end

    describe 'GET /api/v1/ai/security/quarantine/:id' do
      it 'returns quarantine record details' do
        get "/api/v1/ai/security/quarantine/#{quarantine_record.id}",
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end

      it 'returns 404 for non-existent record' do
        get '/api/v1/ai/security/quarantine/nonexistent-id',
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:not_found)
      end
    end

    describe 'POST /api/v1/ai/security/quarantine' do
      it 'quarantines an agent' do
        allow(quarantine_service).to receive(:quarantine!).and_return(quarantine_record)

        post '/api/v1/ai/security/quarantine',
          params: { agent_id: agent.id, severity: 'high', reason: 'Anomalous behavior' }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:created)
        expect(json_response['success']).to be true
      end
    end
  end

  # ============================================================================
  # AGENT IDENTITY
  # ============================================================================

  describe 'AgentIdentityController' do
    let(:identity_service) { instance_double(Ai::Security::AgentIdentityService) }
    let!(:identity) { create(:ai_agent_identity, account: account, agent_id: agent.id) }

    before do
      allow(Ai::Security::AgentIdentityService).to receive(:new).and_return(identity_service)
    end

    describe 'authentication' do
      it 'returns 401 without token' do
        get '/api/v1/ai/security/identities',
          headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe 'authorization' do
      it 'returns 403 without permission' do
        get '/api/v1/ai/security/identities',
          headers: auth_headers_for(no_perms_user)
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'GET /api/v1/ai/security/identities' do
      it 'returns agent identities' do
        get '/api/v1/ai/security/identities',
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
        expect(json_response['data']['items']).to be_an(Array)
      end
    end

    describe 'GET /api/v1/ai/security/identities/:id' do
      it 'returns identity details' do
        get "/api/v1/ai/security/identities/#{identity.id}",
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'POST /api/v1/ai/security/identities' do
      it 'provisions a new identity' do
        new_identity = create(:ai_agent_identity, account: account, agent_id: agent.id)
        allow(identity_service).to receive(:provision!).and_return(new_identity)

        post '/api/v1/ai/security/identities',
          params: { agent_id: agent.id }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:created)
        expect(json_response['success']).to be true
      end
    end

    describe 'POST /api/v1/ai/security/identities/:id/rotate' do
      it 'rotates an identity' do
        new_identity = create(:ai_agent_identity, account: account, agent_id: agent.id)
        allow(identity_service).to receive(:rotate!).and_return(new_identity)

        post "/api/v1/ai/security/identities/#{identity.id}/rotate",
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'POST /api/v1/ai/security/identities/:id/revoke' do
      it 'revokes an identity' do
        allow(identity_service).to receive(:revoke!).and_return({ status: 'revoked' })

        post "/api/v1/ai/security/identities/#{identity.id}/revoke",
          params: { reason: 'Compromised' }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
