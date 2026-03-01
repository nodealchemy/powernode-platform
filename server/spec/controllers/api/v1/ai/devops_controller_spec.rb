# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::DevopsController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/devops" }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.devops.read', account: account) }
  let(:manage_user) { user_with_permissions('ai.devops.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:template) { create(:ai_devops_template, account: account, created_by: manage_user) }
  let(:installation) { create(:ai_devops_template_installation, account: account, devops_template: template, installed_by: manage_user) }

  # =========================================================================
  # TEMPLATES INDEX (ai.devops.read)
  # =========================================================================
  describe "GET /api/v1/ai/devops/templates" do
    let(:path) { "#{base_path}/templates" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.devops.read permission' do
      template # create
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW TEMPLATE (ai.devops.read)
  # =========================================================================
  describe "GET /api/v1/ai/devops/templates/:id" do
    let(:path) { "#{base_path}/templates/#{template.id}" }

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
  # CREATE TEMPLATE (ai.devops.manage)
  # =========================================================================
  describe "POST /api/v1/ai/devops/templates" do
    let(:path) { "#{base_path}/templates" }
    let(:valid_params) do
      {
        name: "New Template",
        description: "A new devops template",
        category: "code_quality",
        template_type: "code_review",
        workflow_definition: { nodes: [], edges: [] }
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
      allow(service).to receive(:create_template).and_return(template)

      post path, params: valid_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UPDATE TEMPLATE (ai.devops.manage)
  # =========================================================================
  describe "PATCH /api/v1/ai/devops/templates/:id" do
    let(:path) { "#{base_path}/templates/#{template.id}" }
    let(:update_params) { { name: "Updated Template Name" } }

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.manage permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'updates the template when user has ai.devops.manage permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # INSTALLATIONS INDEX (ai.devops.read)
  # =========================================================================
  describe "GET /api/v1/ai/devops/installations" do
    let(:path) { "#{base_path}/installations" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.devops.read permission' do
      installation # create
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # INSTALL TEMPLATE (ai.devops.manage)
  # =========================================================================
  describe "POST /api/v1/ai/devops/templates/:template_id/install" do
    let(:path) { "#{base_path}/templates/#{template.id}/install" }
    let(:install_params) { { variable_values: {}, custom_config: {} } }

    it 'returns 401 when unauthenticated' do
      post path, params: install_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.manage permission' do
      post path, params: install_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.devops.manage permission' do
      service = instance_double(::Ai::DevopsService)
      allow(::Ai::DevopsService).to receive(:new).and_return(service)
      allow(service).to receive(:install_template).and_return({ success: true, installation: installation })

      post path, params: install_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UNINSTALL (ai.devops.manage)
  # =========================================================================
  describe "DELETE /api/v1/ai/devops/installations/:id" do
    let(:path) { "#{base_path}/installations/#{installation.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.devops.manage permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'deletes the installation when user has ai.devops.manage permission' do
      delete path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
    end
  end
end
