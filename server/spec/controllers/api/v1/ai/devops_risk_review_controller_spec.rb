# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::DevopsRiskReviewController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/devops" }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.devops.read', account: account) }
  let(:manage_user) { user_with_permissions('ai.devops.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:deployment_risk) { create(:ai_deployment_risk, account: account) }
  let(:code_review) { create(:ai_code_review, account: account) }

  # =========================================================================
  # RISKS INDEX (ai.devops.read)
  # =========================================================================
  describe "GET /api/v1/ai/devops/risks" do
    let(:path) { "#{base_path}/risks" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.devops.read permission' do
      deployment_risk # create
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # ASSESS RISK (ai.devops.manage)
  # =========================================================================
  describe "POST /api/v1/ai/devops/risks/assess" do
    let(:path) { "#{base_path}/risks/assess" }
    let(:valid_params) do
      {
        deployment_type: "application",
        target_environment: "staging",
        change_data: { files_changed: 5 }
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.manage permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.devops.manage permission' do
      service = instance_double(::Ai::DevopsService)
      allow(::Ai::DevopsService).to receive(:new).and_return(service)
      allow(service).to receive(:assess_deployment_risk).and_return({
        success: true, assessment: deployment_risk
      })

      post path, params: valid_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # APPROVE RISK (ai.devops.manage)
  # =========================================================================
  describe "PUT /api/v1/ai/devops/risks/:id/approve" do
    let(:path) { "#{base_path}/risks/#{deployment_risk.id}/approve" }
    let(:approve_params) { { rationale: "Risk is acceptable" } }

    it 'returns 401 when unauthenticated' do
      put path, params: approve_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.manage permission' do
      put path, params: approve_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.devops.manage permission' do
      allow_any_instance_of(::Ai::DeploymentRisk).to receive(:approve!).and_return(true)

      put path, params: approve_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # REJECT RISK (ai.devops.manage)
  # =========================================================================
  describe "PUT /api/v1/ai/devops/risks/:id/reject" do
    let(:path) { "#{base_path}/risks/#{deployment_risk.id}/reject" }
    let(:reject_params) { { rationale: "Too many issues" } }

    it 'returns 401 when unauthenticated' do
      put path, params: reject_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.manage permission' do
      put path, params: reject_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.devops.manage permission' do
      allow_any_instance_of(::Ai::DeploymentRisk).to receive(:reject!).and_return(true)

      put path, params: reject_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # REVIEWS INDEX (ai.devops.read)
  # =========================================================================
  describe "GET /api/v1/ai/devops/reviews" do
    let(:path) { "#{base_path}/reviews" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.devops.read permission' do
      code_review # create
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE REVIEW (ai.devops.manage)
  # =========================================================================
  describe "POST /api/v1/ai/devops/reviews" do
    let(:path) { "#{base_path}/reviews" }
    let(:valid_params) do
      {
        repository_id: SecureRandom.uuid,
        pull_request_number: "42",
        commit_sha: SecureRandom.hex(20),
        base_branch: "main",
        head_branch: "feature/test"
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.manage permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.devops.manage permission' do
      service = instance_double(::Ai::DevopsService)
      allow(::Ai::DevopsService).to receive(:new).and_return(service)
      allow(service).to receive(:create_code_review).and_return({
        success: true, review: code_review
      })

      post path, params: valid_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # SHOW REVIEW (ai.devops.read)
  # =========================================================================
  describe "GET /api/v1/ai/devops/reviews/:id" do
    let(:path) { "#{base_path}/reviews/#{code_review.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.devops.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end
end
