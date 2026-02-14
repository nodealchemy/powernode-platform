# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::Security::QuarantineController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/security/quarantine" }

  # Users
  let(:security_user) { user_with_permissions('ai.security.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:agent) { create(:ai_agent, account: account) }
  let(:quarantine_record) { create(:ai_quarantine_record, account: account, agent_id: agent.id) }

  # Service doubles
  let(:quarantine_service) { instance_double(Ai::Security::QuarantineService) }
  let(:audit_service) { instance_double(Ai::Security::SecurityAuditService) }

  before do
    allow(Ai::Security::QuarantineService).to receive(:new).and_return(quarantine_service)
    allow(Ai::Security::SecurityAuditService).to receive(:new).and_return(audit_service)
  end

  # =========================================================================
  # INDEX (ai.security.manage)
  # =========================================================================
  describe "GET /api/v1/ai/security/quarantine" do
    let(:path) { base_path }

    before do
      quarantine_record # create
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.security.manage permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns paginated quarantine records' do
      get path, headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['items']).to be_an(Array)
      expect(json_response['data']['pagination']).to be_present
    end

    it 'filters by status' do
      get path, params: { status: 'active' }, headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:success)
    end

    it 'filters by agent_id' do
      get path, params: { agent_id: agent.id }, headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW (ai.security.manage)
  # =========================================================================
  describe "GET /api/v1/ai/security/quarantine/:id" do
    let(:path) { "#{base_path}/#{quarantine_record.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns quarantine record details' do
      get path, headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['id']).to eq(quarantine_record.id)
      expect(json_response['data']['severity']).to be_present
    end

    it 'returns not found for nonexistent record' do
      get "#{base_path}/#{SecureRandom.uuid}", headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # QUARANTINE AGENT (ai.security.manage)
  # =========================================================================
  describe "POST /api/v1/ai/security/quarantine" do
    let(:path) { base_path }
    let(:params) do
      { agent_id: agent.id, severity: "high", reason: "Anomalous behavior", source: "manual" }
    end

    before do
      allow(quarantine_service).to receive(:quarantine!).and_return(quarantine_record)
    end

    it 'returns 401 when unauthenticated' do
      post path, params: params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, params: params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'quarantines the agent and returns record' do
      post path, params: params.to_json, headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['id']).to eq(quarantine_record.id)
    end

    it 'returns not found for nonexistent agent' do
      post path, params: { agent_id: SecureRandom.uuid, reason: "test" }.to_json,
           headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # ESCALATE (ai.security.manage)
  # =========================================================================
  describe "POST /api/v1/ai/security/quarantine/:id/escalate" do
    let(:path) { "#{base_path}/#{quarantine_record.id}/escalate" }
    let(:escalated_record) { create(:ai_quarantine_record, :high, account: account, agent_id: agent.id) }
    let(:params) { { new_severity: "critical" } }

    before do
      allow(quarantine_service).to receive(:escalate!).and_return(escalated_record)
    end

    it 'returns 401 when unauthenticated' do
      post path, params: params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, params: params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'escalates the quarantine record' do
      post path, params: params.to_json, headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['id']).to eq(escalated_record.id)
    end

    it 'returns not found for nonexistent record' do
      post "#{base_path}/#{SecureRandom.uuid}/escalate", params: params.to_json,
           headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # RESTORE (ai.security.manage)
  # =========================================================================
  describe "POST /api/v1/ai/security/quarantine/:id/restore" do
    let(:path) { "#{base_path}/#{quarantine_record.id}/restore" }
    let(:restored_record) { create(:ai_quarantine_record, :restored, account: account, agent_id: agent.id) }

    before do
      allow(quarantine_service).to receive(:restore!).and_return(restored_record)
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'restores the quarantined agent' do
      post path, headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['status']).to eq('restored')
    end

    it 'returns not found for nonexistent record' do
      post "#{base_path}/#{SecureRandom.uuid}/restore", headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # SECURITY REPORT (ai.security.manage)
  # =========================================================================
  describe "GET /api/v1/ai/security/quarantine/report" do
    let(:path) { "#{base_path}/report" }

    before do
      allow(audit_service).to receive(:security_report).and_return({
        total_incidents: 5, risk_level: "medium"
      })
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns security report data' do
      get path, headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to be_present
    end
  end

  # =========================================================================
  # COMPLIANCE MATRIX (ai.security.manage)
  # =========================================================================
  describe "GET /api/v1/ai/security/quarantine/compliance" do
    let(:path) { "#{base_path}/compliance" }

    before do
      allow(audit_service).to receive(:compliance_matrix).and_return({
        ASI01: { status: "compliant" }
      })
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns compliance matrix data' do
      get path, headers: auth_headers_for(security_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['matrix']).to be_present
    end
  end
end
