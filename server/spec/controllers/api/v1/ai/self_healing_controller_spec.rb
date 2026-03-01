# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::SelfHealingController", type: :request do
  let(:account) { create(:account) }
  let(:monitoring_user) { user_with_permissions('ai.monitoring.read', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  let(:base_path) { "/api/v1/ai/self_healing" }

  before do
    allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(true)
    allow(::Ai::ProviderCircuitBreakerService).to receive(:all_provider_stats).and_return([])
  end

  # =========================================================================
  # REMEDIATION LOGS (ai.monitoring.read)
  # =========================================================================
  describe "GET /api/v1/ai/self_healing/remediation_logs" do
    let(:path) { "#{base_path}/remediation_logs" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.monitoring.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with remediation logs and health summary' do
      create(:ai_remediation_log, :successful, account: account)

      get path, headers: auth_headers_for(monitoring_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('remediation_logs')
      expect(json_response['data']).to have_key('health_summary')
    end

    it 'filters by action_type when provided' do
      create(:ai_remediation_log, :provider_failover, account: account)
      create(:ai_remediation_log, :workflow_retry, account: account)

      get path, params: { action_type: 'provider_failover' },
                headers: auth_headers_for(monitoring_user)
      expect(response).to have_http_status(:success)
      logs = json_response['data']['remediation_logs']
      expect(logs).to all(include('action_type' => 'provider_failover'))
    end
  end

  # =========================================================================
  # HEALTH SUMMARY (ai.monitoring.read)
  # =========================================================================
  describe "GET /api/v1/ai/self_healing/health_summary" do
    let(:path) { "#{base_path}/health_summary" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with health summary data' do
      get path, headers: auth_headers_for(monitoring_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('overall_status')
      expect(json_response['data']).to have_key('success_rate')
      expect(json_response['data']).to have_key('feature_flag_enabled')
    end

    it 'reports healthy status when no remediations exist' do
      get path, headers: auth_headers_for(monitoring_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['overall_status']).to eq('healthy')
      expect(json_response['data']['success_rate']).to eq(100.0)
    end
  end

  # =========================================================================
  # CORRELATIONS (ai.monitoring.read)
  # =========================================================================
  describe "GET /api/v1/ai/self_healing/correlations" do
    let(:path) { "#{base_path}/correlations" }

    let(:mock_correlator) { instance_double(::Ai::SelfHealing::CrossSystemCorrelator) }

    before do
      allow(::Ai::SelfHealing::CrossSystemCorrelator).to receive(:new).and_return(mock_correlator)
      allow(mock_correlator).to receive(:correlate_failures).and_return([])
      allow(mock_correlator).to receive(:devops_health).and_return({ status: "healthy" })
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with correlations and devops health' do
      get path, headers: auth_headers_for(monitoring_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('correlations')
      expect(json_response['data']).to have_key('devops_health')
      expect(json_response['data']).to have_key('timestamp')
    end
  end
end
