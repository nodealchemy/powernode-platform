# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::Workflows - Run Actions", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.workflows.read', account: account) }
  let(:execute_user) { user_with_permissions('ai.workflows.execute', account: account) }
  let(:full_user) { user_with_permissions('ai.workflows.read', 'ai.workflows.execute', 'ai.workflows.update', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:workflow) { create(:ai_workflow, account: account) }
  let!(:workflow_run) { create(:ai_workflow_run, workflow: workflow, account: account) }

  # =========================================================================
  # RUNS INDEX (nested under workflow)
  # =========================================================================
  describe "GET /api/v1/ai/workflows/:workflow_id/runs" do
    let(:path) { "/api/v1/ai/workflows/#{workflow.id}/runs" }

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
    end
  end

  # =========================================================================
  # RUN SHOW (uses run_id UUID param, not primary key id)
  # =========================================================================
  describe "GET /api/v1/ai/workflows/:workflow_id/runs/:run_id" do
    let(:path) { "/api/v1/ai/workflows/#{workflow.id}/runs/#{workflow_run.run_id}" }

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
  # RUN CANCEL
  # =========================================================================
  describe "POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/cancel" do
    let(:path) { "/api/v1/ai/workflows/#{workflow.id}/runs/#{workflow_run.run_id}/cancel" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.execute permission' do
      post path, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # RUN PAUSE
  # =========================================================================
  describe "POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/pause" do
    let(:path) { "/api/v1/ai/workflows/#{workflow.id}/runs/#{workflow_run.run_id}/pause" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.execute permission' do
      post path, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # RUN RESUME
  # =========================================================================
  describe "POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/resume" do
    let(:path) { "/api/v1/ai/workflows/#{workflow.id}/runs/#{workflow_run.run_id}/resume" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.execute permission' do
      post path, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # RUN LOGS
  # =========================================================================
  describe "GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/logs" do
    let(:path) { "/api/v1/ai/workflows/#{workflow.id}/runs/#{workflow_run.run_id}/logs" }

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
  # RUN NODE EXECUTIONS
  # =========================================================================
  describe "GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/node_executions" do
    let(:path) { "/api/v1/ai/workflows/#{workflow.id}/runs/#{workflow_run.run_id}/node_executions" }

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
end
