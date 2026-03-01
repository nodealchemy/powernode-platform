# frozen_string_literal: true

require 'rails_helper'

# Tests for the Security namespace controllers:
# - AnomalyDetectionsController
# - PiiRedactionsController
# - QuarantineController
# - AgentIdentityController

RSpec.describe 'Api::V1::Ai::Security', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.security.manage']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }
  let(:agent) { create(:ai_agent, account: account, creator: user) }

  # ============================================================================
  # ANOMALY DETECTION
  # ============================================================================

  describe 'AnomalyDetectionsController' do
    let(:anomaly_service) { instance_double(Ai::Security::AgentAnomalyDetectionService) }

    before do
      allow(Ai::Security::AgentAnomalyDetectionService).to receive(:new).and_return(anomaly_service)
    end

    describe 'authentication' do
      it 'returns 401 without token for analyze' do
        post '/api/v1/ai/security/anomaly_detection/analyze', params: { agent_id: agent.id }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe 'authorization' do
      it 'returns 403 without ai.security.manage permission' do
        post '/api/v1/ai/security/anomaly_detection/analyze',
          params: { agent_id: agent.id }.to_json,
          headers: auth_headers_for(no_perms_user)
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'POST /api/v1/ai/security/anomaly_detection/analyze' do
      it 'analyzes agent behavior' do
        allow(anomaly_service).to receive(:analyze_agent).and_return({
          risk_score: 0.15, anomalies: [], recommendation: 'normal'
        })

        post '/api/v1/ai/security/anomaly_detection/analyze',
          params: { agent_id: agent.id, window_minutes: 60 }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(json_response['data']).to be_present
      end

      it 'returns 404 for non-existent agent' do
        post '/api/v1/ai/security/anomaly_detection/analyze',
          params: { agent_id: 'nonexistent' }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:not_found)
      end
    end

    describe 'POST /api/v1/ai/security/anomaly_detection/check_action' do
      it 'checks agent action' do
        allow(anomaly_service).to receive(:check_action).and_return({
          allowed: true, risk_level: 'low'
        })

        post '/api/v1/ai/security/anomaly_detection/check_action',
          params: { agent_id: agent.id, action_type: 'api_call', action_context: {} }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'POST /api/v1/ai/security/anomaly_detection/detect_injection' do
      it 'detects prompt injection' do
        allow(anomaly_service).to receive(:detect_prompt_injection).and_return({
          injection_detected: false, confidence: 0.1
        })

        post '/api/v1/ai/security/anomaly_detection/detect_injection',
          params: { content: 'Normal question about Ruby on Rails' }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'POST /api/v1/ai/security/anomaly_detection/detect_rogue' do
      it 'detects rogue agent behavior' do
        allow(anomaly_service).to receive(:detect_rogue_behavior).and_return({
          is_rogue: false, indicators: []
        })

        post '/api/v1/ai/security/anomaly_detection/detect_rogue',
          params: { agent_id: agent.id }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'GET /api/v1/ai/security/anomaly_detection/report' do
      it 'returns security report' do
        allow(anomaly_service).to receive(:security_report).and_return({
          total_anomalies: 5, risk_distribution: {}
        })

        get '/api/v1/ai/security/anomaly_detection/report',
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
        expect(json_response['data']).to be_present
      end
    end
  end

  # ============================================================================
  # PII REDACTION
  # ============================================================================

  describe 'PiiRedactionsController' do
    let(:pii_service) { instance_double(Ai::Security::PiiRedactionService) }

    before do
      allow(Ai::Security::PiiRedactionService).to receive(:new).and_return(pii_service)
    end

    describe 'authentication' do
      it 'returns 401 without token for scan' do
        post '/api/v1/ai/security/pii_redaction/scan',
          params: { content: 'test' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe 'authorization' do
      it 'returns 403 without ai.security.manage permission' do
        post '/api/v1/ai/security/pii_redaction/scan',
          params: { content: 'test' }.to_json,
          headers: auth_headers_for(no_perms_user)
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'POST /api/v1/ai/security/pii_redaction/scan' do
      it 'scans text for PII' do
        allow(pii_service).to receive(:scan).and_return({
          detections: [], pii_found: false
        })

        post '/api/v1/ai/security/pii_redaction/scan',
          params: { content: 'Hello, my name is John' }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
      end
    end

    describe 'POST /api/v1/ai/security/pii_redaction/redact' do
      it 'redacts PII from text' do
        allow(pii_service).to receive(:redact).and_return({
          redacted_text: 'Hello, my name is [REDACTED]', detections_count: 1
        })

        post '/api/v1/ai/security/pii_redaction/redact',
          params: { content: 'Hello, my name is John Doe' }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'POST /api/v1/ai/security/pii_redaction/apply_policy' do
      it 'applies classification policy' do
        allow(pii_service).to receive(:apply_policy).and_return({
          result: 'clean', policy_applied: 'internal'
        })

        post '/api/v1/ai/security/pii_redaction/apply_policy',
          params: { content: 'Test content', classification_level: 'internal' }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'POST /api/v1/ai/security/pii_redaction/check_output' do
      it 'checks if output is safe' do
        allow(pii_service).to receive(:safe_to_output?).and_return(true)

        post '/api/v1/ai/security/pii_redaction/check_output',
          params: { content: 'Safe text output' }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
        expect(json_response['data']['safe']).to be true
      end
    end

    describe 'POST /api/v1/ai/security/pii_redaction/batch_scan' do
      it 'batch scans multiple texts' do
        allow(pii_service).to receive(:batch_scan).and_return({
          results: [{ pii_found: false }, { pii_found: true }]
        })

        post '/api/v1/ai/security/pii_redaction/batch_scan',
          params: { contents: ['Text 1', 'Text with SSN 123-45-6789'] }.to_json,
          headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end
  end

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
