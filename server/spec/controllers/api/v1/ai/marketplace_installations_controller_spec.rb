# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::MarketplaceInstallationsController", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.workflows.read', account: account) }
  let(:create_user) { user_with_permissions('ai.workflows.create', account: account) }
  let(:update_user) { user_with_permissions('ai.workflows.update', account: account) }
  let(:delete_user) { user_with_permissions('ai.workflows.delete', account: account) }
  let(:manage_user) { user_with_permissions('ai.workflows.manage', account: account) }
  let(:full_user) do
    user_with_permissions(
      'ai.workflows.read', 'ai.workflows.create',
      'ai.workflows.update', 'ai.workflows.delete', 'ai.workflows.manage',
      account: account
    )
  end
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:template) { create(:ai_workflow_template, is_public: true, account: account, created_by_user: full_user) }
  let(:installation_service) { instance_double(Ai::Marketplace::InstallationService) }

  before do
    allow(Ai::Marketplace::InstallationService).to receive(:new).and_return(installation_service)
  end

  # =========================================================================
  # INSTALLATIONS INDEX (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/marketplace/installations" do
    let(:path) { "/api/v1/ai/marketplace/installations" }

    before do
      allow(installation_service).to receive(:list_installations).and_return({
        installations: [{ id: 'inst-1', template_name: 'Test' }],
        pagination: { current_page: 1, per_page: 25, total_pages: 1, total_count: 1 }
      })
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns list of installations' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['installations']).to be_an(Array)
      expect(json_response['data']['pagination']).to be_present
    end
  end

  # =========================================================================
  # INSTALLATION SHOW (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/marketplace/installations/:id" do
    it 'returns 401 when unauthenticated' do
      get "/api/v1/ai/marketplace/installations/some-id", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get "/api/v1/ai/marketplace/installations/some-id", headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns installation details' do
      allow(installation_service).to receive(:get_installation).with('some-id').and_return({
        success: true,
        installation: { id: 'some-id', template_name: 'Test Template' }
      })

      get "/api/v1/ai/marketplace/installations/some-id", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['installation']).to be_present
    end

    it 'returns 404 when installation not found' do
      allow(installation_service).to receive(:get_installation).with('nonexistent').and_return({
        success: false, error: 'Installation not found'
      })

      get "/api/v1/ai/marketplace/installations/nonexistent", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # INSTALLATION DESTROY (ai.workflows.delete)
  # =========================================================================
  describe "DELETE /api/v1/ai/marketplace/installations/:id" do
    it 'returns 401 when unauthenticated' do
      delete "/api/v1/ai/marketplace/installations/some-id", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.delete permission' do
      delete "/api/v1/ai/marketplace/installations/some-id", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'deletes an installation' do
      allow(installation_service).to receive(:uninstall).and_return({
        success: true, message: 'Template uninstalled successfully'
      })

      delete "/api/v1/ai/marketplace/installations/some-id", headers: auth_headers_for(delete_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['message']).to include('uninstalled')
    end

    it 'returns 404 when installation not found' do
      allow(installation_service).to receive(:uninstall).and_return({
        success: false, error: 'Installation not found'
      })

      delete "/api/v1/ai/marketplace/installations/nonexistent", headers: auth_headers_for(delete_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # INSTALL (ai.workflows.create)
  # =========================================================================
  describe "POST /api/v1/ai/marketplace/templates/:id/install" do
    let(:mock_workflow) { create(:ai_workflow, account: account, creator: full_user) }
    let(:mock_subscription) do
      create(:marketplace_subscription,
        account: account,
        subscribable: template,
        metadata: { 'template_version' => template.version, 'workflow_id' => mock_workflow.id }
      )
    end

    it 'returns 401 when unauthenticated' do
      post "/api/v1/ai/marketplace/templates/#{template.id}/install", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.create permission' do
      post "/api/v1/ai/marketplace/templates/#{template.id}/install", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'installs a template' do
      allow(installation_service).to receive(:install).and_return({
        success: true,
        subscription: mock_subscription,
        workflow: mock_workflow,
        message: 'Template installed successfully'
      })

      post "/api/v1/ai/marketplace/templates/#{template.id}/install",
        params: { custom_configuration: { key: 'value' } }.to_json,
        headers: auth_headers_for(create_user)
      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
      expect(json_response['data']['installation']).to be_present
      expect(json_response['data']['workflow']).to be_present
    end

    it 'returns error on install failure' do
      allow(installation_service).to receive(:install).and_return({
        success: false, error: 'Already installed'
      })

      post "/api/v1/ai/marketplace/templates/#{template.id}/install",
        headers: auth_headers_for(create_user)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 404 for nonexistent template' do
      post "/api/v1/ai/marketplace/templates/nonexistent/install",
        headers: auth_headers_for(create_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # CHECK UPDATES (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/marketplace/updates" do
    let(:path) { "/api/v1/ai/marketplace/updates" }

    before do
      allow(installation_service).to receive(:check_for_updates).and_return({
        updates_available: []
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

    it 'returns update availability' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['updates_available']).to be_an(Array)
    end
  end

  # =========================================================================
  # APPLY UPDATES (ai.workflows.manage)
  # =========================================================================
  describe "POST /api/v1/ai/marketplace/updates/apply" do
    let(:path) { "/api/v1/ai/marketplace/updates/apply" }

    before do
      allow(installation_service).to receive(:apply_all_updates).and_return({
        successful: 2, failed: 0, total_attempted: 2
      })
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.manage permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'applies updates' do
      post path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['message']).to include('Updated')
    end
  end

  # =========================================================================
  # RATE (ai.workflows.update)
  # =========================================================================
  describe "POST /api/v1/ai/marketplace/templates/:id/rate" do
    it 'returns 401 when unauthenticated' do
      post "/api/v1/ai/marketplace/templates/#{template.id}/rate",
        params: { rating: 5 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.update permission' do
      post "/api/v1/ai/marketplace/templates/#{template.id}/rate",
        params: { rating: 5 }.to_json,
        headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'rates a template' do
      allow(installation_service).to receive(:rate_template).and_return({
        success: true, template_id: template.id, rating: 5,
        new_average: 5.0, total_ratings: 1, message: 'Template rated successfully'
      })

      post "/api/v1/ai/marketplace/templates/#{template.id}/rate",
        params: { rating: 5, feedback: { comment: 'Great!' } }.to_json,
        headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['message']).to include('rated successfully')
    end

    it 'validates rating range' do
      post "/api/v1/ai/marketplace/templates/#{template.id}/rate",
        params: { rating: 10 }.to_json,
        headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:bad_request)
    end

    it 'requires rating parameter' do
      post "/api/v1/ai/marketplace/templates/#{template.id}/rate",
        params: {}.to_json,
        headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 404 for nonexistent template' do
      post "/api/v1/ai/marketplace/templates/nonexistent/rate",
        params: { rating: 5 }.to_json,
        headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:not_found)
    end
  end
end
