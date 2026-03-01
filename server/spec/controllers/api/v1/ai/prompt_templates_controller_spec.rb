# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::PromptTemplatesController", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.prompt_templates.read', account: account) }
  let(:write_user) { user_with_permissions('ai.prompt_templates.read', 'ai.prompt_templates.write', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:prompt_template) { create(:shared_prompt_template, account: account, created_by: read_user) }

  # =========================================================================
  # INDEX (GET /api/v1/ai/prompt_templates)
  # =========================================================================
  describe "GET /api/v1/ai/prompt_templates" do
    let(:path) { "/api/v1/ai/prompt_templates" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.prompt_templates.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.prompt_templates.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['prompt_templates']).to be_an(Array)
    end
  end

  # =========================================================================
  # SHOW (GET /api/v1/ai/prompt_templates/:id)
  # =========================================================================
  describe "GET /api/v1/ai/prompt_templates/:id" do
    let(:path) { "/api/v1/ai/prompt_templates/#{prompt_template.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.prompt_templates.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.prompt_templates.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['prompt_template']).to be_a(Hash)
    end
  end

  # =========================================================================
  # CREATE (POST /api/v1/ai/prompt_templates)
  # =========================================================================
  describe "POST /api/v1/ai/prompt_templates" do
    let(:path) { "/api/v1/ai/prompt_templates" }
    let(:valid_params) do
      {
        prompt_template: {
          name: "New Template",
          content: "Hello {{ name }}",
          category: "custom",
          description: "A test template"
        }
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.prompt_templates.write permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.prompt_templates.write permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(write_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UPDATE (PATCH /api/v1/ai/prompt_templates/:id)
  # =========================================================================
  describe "PATCH /api/v1/ai/prompt_templates/:id" do
    let(:path) { "/api/v1/ai/prompt_templates/#{prompt_template.id}" }
    let(:update_params) do
      { prompt_template: { name: "Updated Template" } }
    end

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.prompt_templates.write permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.prompt_templates.write permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(write_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
    end
  end

  # =========================================================================
  # DESTROY (DELETE /api/v1/ai/prompt_templates/:id)
  # =========================================================================
  describe "DELETE /api/v1/ai/prompt_templates/:id" do
    let(:path) { "/api/v1/ai/prompt_templates/#{prompt_template.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.prompt_templates.write permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.prompt_templates.write permission' do
      delete path, headers: auth_headers_for(write_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
    end
  end

  # =========================================================================
  # PREVIEW (POST /api/v1/ai/prompt_templates/:id/preview)
  # =========================================================================
  describe "POST /api/v1/ai/prompt_templates/:id/preview" do
    let(:path) { "/api/v1/ai/prompt_templates/#{prompt_template.id}/preview" }

    it 'returns 401 when unauthenticated' do
      post path, params: { variables: { context: "hello" } }.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.prompt_templates.read permission' do
      post path, params: { variables: { context: "hello" } }.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.prompt_templates.read permission' do
      post path, params: { variables: { context: "hello" } }.to_json, headers: auth_headers_for(read_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # DUPLICATE (POST /api/v1/ai/prompt_templates/:id/duplicate)
  # =========================================================================
  describe "POST /api/v1/ai/prompt_templates/:id/duplicate" do
    let(:path) { "/api/v1/ai/prompt_templates/#{prompt_template.id}/duplicate" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.prompt_templates.write permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.prompt_templates.write permission' do
      post path, headers: auth_headers_for(write_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
