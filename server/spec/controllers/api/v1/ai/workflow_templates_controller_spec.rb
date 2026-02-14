# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::WorkflowTemplatesController", type: :request do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.workflows.read', account: account) }
  let(:update_user) { user_with_permissions('ai.workflows.update', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data - use `creator` (plain user) to avoid permission conflicts during lazy loading
  let(:workflow) { create(:ai_workflow, account: account, creator: creator) }
  let(:template_workflow) { create(:ai_workflow, :template, account: account, creator: creator) }

  # =========================================================================
  # TEMPLATES INDEX (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/workflows/templates" do
    let(:path) { "/api/v1/ai/workflows/templates" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.read permission' do
      template_workflow # create
      get path, headers: auth_headers_for(read_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # CONVERT TO TEMPLATE (ai.workflows.update)
  # =========================================================================
  describe "POST /api/v1/ai/workflows/:id/convert_to_template" do
    let(:path) { "/api/v1/ai/workflows/#{workflow.id}/convert_to_template" }
    let(:convert_params) { { category: "automation", visibility: "account" } }

    it 'returns 401 when unauthenticated' do
      post path, params: convert_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.update permission' do
      post path, params: convert_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.update permission' do
      result = double(success?: true, workflow: workflow)
      service = instance_double(::Ai::Workflows::TemplateService)
      allow(::Ai::Workflows::TemplateService).to receive(:new).and_return(service)
      allow(service).to receive(:convert_to_template).and_return(result)

      post path, params: convert_params.to_json, headers: auth_headers_for(update_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # CREATE FROM TEMPLATE (ai.workflows.update)
  # =========================================================================
  describe "POST /api/v1/ai/workflows/:id/create_from_template" do
    let(:path) { "/api/v1/ai/workflows/#{template_workflow.id}/create_from_template" }
    let(:create_params) { { name: "New Workflow From Template" } }

    it 'returns 401 when unauthenticated' do
      post path, params: create_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.update permission' do
      post path, params: create_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.update permission' do
      new_workflow = create(:ai_workflow, account: account, creator: creator)
      result = double(success?: true, workflow: new_workflow)
      service = instance_double(::Ai::Workflows::TemplateService)
      allow(::Ai::Workflows::TemplateService).to receive(:new).and_return(service)
      allow(service).to receive(:create_workflow_from_source).and_return(result)

      post path, params: create_params.to_json, headers: auth_headers_for(update_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # CONVERT TO WORKFLOW (ai.workflows.update)
  # =========================================================================
  describe "POST /api/v1/ai/workflows/:id/convert_to_workflow" do
    let(:path) { "/api/v1/ai/workflows/#{template_workflow.id}/convert_to_workflow" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'converts template to workflow when user has ai.workflows.update permission' do
      post path, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:success)
      template_workflow.reload
      expect(template_workflow.is_template).to eq(false)
    end
  end

  # =========================================================================
  # CONVERT TO WORKFLOW - error case
  # =========================================================================
  describe "POST /api/v1/ai/workflows/:id/convert_to_workflow (non-template)" do
    let(:path) { "/api/v1/ai/workflows/#{workflow.id}/convert_to_workflow" }

    it 'returns error when workflow is not a template' do
      post path, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
