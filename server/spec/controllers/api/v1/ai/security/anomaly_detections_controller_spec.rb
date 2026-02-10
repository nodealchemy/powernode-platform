# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::Security::AnomalyDetectionsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:security_user) { create(:user, account: account, permissions: ['ai.security.manage']) }
  let(:agent) { create(:ai_agent, account: account) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'

    allow_any_instance_of(Ai::Security::AgentAnomalyDetectionService).to receive(:analyze_agent).and_return({
      anomalies: [], risk_level: "low", recommendations: []
    })

    allow_any_instance_of(Ai::Security::AgentAnomalyDetectionService).to receive(:check_action).and_return({
      allowed: true, reason: nil, enforcement: nil
    })

    allow_any_instance_of(Ai::Security::AgentAnomalyDetectionService).to receive(:detect_prompt_injection).and_return({
      detected: false, patterns: [], confidence: 0.0, action_taken: "none"
    })

    allow_any_instance_of(Ai::Security::AgentAnomalyDetectionService).to receive(:detect_rogue_behavior).and_return({
      rogue: false, indicators: [], recommended_action: "none"
    })

    allow_any_instance_of(Ai::Security::AgentAnomalyDetectionService).to receive(:security_report).and_return({
      account_id: account.id, period_hours: 24, total_agents: 0,
      agents_with_anomalies: 0, rogue_agents_detected: 0,
      open_violations: 0, critical_violations: 0,
      overall_risk: "low", agent_reports: [], recommendations: []
    })
  end

  describe 'POST #analyze' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns analysis data' do
        post :analyze, params: { agent_id: agent.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('anomalies', 'risk_level', 'recommendations')
      end

      it 'passes window_minutes parameter' do
        expect_any_instance_of(Ai::Security::AgentAnomalyDetectionService).to receive(:analyze_agent).with(
          hash_including(agent: agent, window_minutes: 120)
        )

        post :analyze, params: { agent_id: agent.id, window_minutes: 120 }

        expect(response).to have_http_status(:success)
      end

      it 'returns not found for invalid agent_id' do
        post :analyze, params: { agent_id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :analyze, params: { agent_id: agent.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #check_action' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns action check result' do
        post :check_action, params: { agent_id: agent.id, action_type: 'execute_code' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('allowed')
      end

      it 'returns not found for invalid agent_id' do
        post :check_action, params: { agent_id: SecureRandom.uuid, action_type: 'execute_code' }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :check_action, params: { agent_id: agent.id, action_type: 'execute_code' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #detect_injection' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns injection detection result' do
        allow_any_instance_of(Ai::Security::AgentAnomalyDetectionService).to receive(:detect_prompt_injection)
          .with(hash_including(:text))
          .and_return({ detected: false, patterns: [], confidence: 0.0, action_taken: "none" })

        post :detect_injection, params: { content: 'Hello world' }

        json = JSON.parse(response.body)
        expect(response).to have_http_status(:success), "Expected success but got #{response.status}: #{json}"
        expect(json['success']).to be true
        expect(json['data']).to include('detected', 'patterns', 'confidence', 'action_taken')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :detect_injection, params: { content: 'test' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #detect_rogue' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns rogue detection result' do
        post :detect_rogue, params: { agent_id: agent.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('rogue', 'indicators', 'recommended_action')
      end

      it 'returns not found for invalid agent_id' do
        post :detect_rogue, params: { agent_id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :detect_rogue, params: { agent_id: agent.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #report' do
    context 'with valid permissions' do
      before { sign_in security_user }

      it 'returns security report' do
        get :report

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('overall_risk', 'agent_reports')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :report

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
