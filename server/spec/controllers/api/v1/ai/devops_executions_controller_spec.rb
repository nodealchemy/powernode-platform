# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::DevopsExecutionsController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/devops" }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.devops.read', account: account) }
  let(:manage_user) { user_with_permissions('ai.devops.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:execution) { create(:ai_pipeline_execution, account: account) }

  # =========================================================================
  # EXECUTIONS INDEX (ai.devops.read)
  # =========================================================================
  describe "GET /api/v1/ai/devops/executions" do
    let(:path) { "#{base_path}/executions" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.devops.read permission' do
      execution # create
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE EXECUTION (ai.devops.manage)
  # =========================================================================
  describe "POST /api/v1/ai/devops/executions" do
    let(:path) { "#{base_path}/executions" }
    let(:valid_params) do
      {
        pipeline_type: "pr_review",
        trigger_source: "manual",
        trigger_event: "manual.trigger",
        input_data: { files_changed: 3 }
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
      allow(service).to receive(:execute_pipeline).and_return({ success: true, execution: execution })

      post path, params: valid_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # SHOW EXECUTION (ai.devops.read)
  # =========================================================================
  describe "GET /api/v1/ai/devops/executions/:id" do
    let(:path) { "#{base_path}/executions/#{execution.id}" }

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

  # =========================================================================
  # ANALYTICS (ai.devops.read)
  # =========================================================================
  describe "GET /api/v1/ai/devops/analytics" do
    let(:path) { "#{base_path}/analytics" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.devops.read permission' do
      service = instance_double(::Ai::DevopsService)
      allow(::Ai::DevopsService).to receive(:new).and_return(service)
      allow(service).to receive(:get_pipeline_analytics).and_return({
        total_executions: 0, success_rate: 0, average_duration: 0
      })

      get path, headers: auth_headers_for(read_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
