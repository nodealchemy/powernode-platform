# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::WorkflowValidationsController", type: :request do
  let(:account) { create(:account) }
  let(:base_workflow) { create(:ai_workflow, account: account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.workflows.read', account: account) }
  let(:execute_user) { user_with_permissions('ai.workflows.execute', account: account) }
  let(:full_user) { user_with_permissions('ai.workflows.read', 'ai.workflows.execute', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:validation) { create(:workflow_validation, workflow: base_workflow) }

  # =========================================================================
  # INDEX
  # =========================================================================
  describe "GET /api/v1/ai/workflows/:workflow_id/validations" do
    let(:path) { "/api/v1/ai/workflows/#{base_workflow.id}/validations" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['validations']).to be_an(Array)
    end
  end

  # =========================================================================
  # SHOW
  # =========================================================================
  describe "GET /api/v1/ai/workflows/:workflow_id/validations/:id" do
    let(:path) { "/api/v1/ai/workflows/#{base_workflow.id}/validations/#{validation.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response_data['validation']).to be_a(Hash)
      expect(json_response_data['validation']['id']).to eq(validation.id)
    end
  end

  # =========================================================================
  # CREATE
  # =========================================================================
  describe "POST /api/v1/ai/workflows/:workflow_id/validations" do
    let(:path) { "/api/v1/ai/workflows/#{base_workflow.id}/validations" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.execute permission' do
      # The create action calls perform_workflow_validation which uses WorkflowValidationService
      # We stub it to avoid dependency on the full validation service
      allow_any_instance_of(::Ai::WorkflowValidationService).to receive(:validate).and_return(
        overall_status: 'valid',
        health_score: 100,
        total_nodes: 3,
        validated_nodes: 3,
        issues: []
      )

      post path, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # LATEST
  # =========================================================================
  describe "GET /api/v1/ai/workflows/:workflow_id/validations/latest" do
    let(:path) { "/api/v1/ai/workflows/#{base_workflow.id}/validations/latest" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # AUTO_FIX
  # =========================================================================
  describe "POST /api/v1/ai/workflows/:workflow_id/validations/auto_fix" do
    let(:path) { "/api/v1/ai/workflows/#{base_workflow.id}/validations/auto_fix" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.execute permission' do
      allow_any_instance_of(::Ai::WorkflowAutoFixService).to receive(:fix_all).and_return(
        fixed_count: 0, fixes_applied: [], errors: [], health_score_improvement: 0
      )
      allow_any_instance_of(::Ai::WorkflowValidationService).to receive(:validate).and_return(
        overall_status: 'valid', health_score: 100, total_nodes: 3, validated_nodes: 3, issues: []
      )

      post path, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # PREVIEW_FIXES
  # =========================================================================
  describe "GET /api/v1/ai/workflows/:workflow_id/validations/preview_fixes" do
    let(:path) { "/api/v1/ai/workflows/#{base_workflow.id}/validations/preview_fixes" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.execute permission' do
      allow_any_instance_of(::Ai::WorkflowAutoFixService).to receive(:preview_fixes).and_return(
        fixable_count: 0, planned_fixes: [], estimated_health_score_improvement: 0
      )

      get path, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
