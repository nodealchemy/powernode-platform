# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::McpAppsController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/mcp_apps" }

  # Users
  let(:read_user) { user_with_permissions('ai.agents.read', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:mcp_app) { create(:ai_mcp_app, account: account) }

  # Service double
  let(:renderer_service) { instance_double(Ai::McpApps::RendererService) }

  before do
    allow(Ai::McpApps::RendererService).to receive(:new).and_return(renderer_service)
  end

  # =========================================================================
  # INDEX
  # =========================================================================
  describe "GET /api/v1/ai/mcp_apps" do
    let(:path) { base_path }

    before do
      allow(renderer_service).to receive(:list_apps).and_return([mcp_app])
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.agents.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with list of apps' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['apps']).to be_an(Array)
    end
  end

  # =========================================================================
  # SHOW
  # =========================================================================
  describe "GET /api/v1/ai/mcp_apps/:id" do
    let(:path) { "#{base_path}/#{mcp_app.id}" }

    before do
      allow(renderer_service).to receive(:get_app).with(mcp_app.id.to_s).and_return(mcp_app)
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with app details' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['app']['id']).to eq(mcp_app.id)
    end

    it 'returns not found for nonexistent app' do
      allow(renderer_service).to receive(:get_app).and_raise(ActiveRecord::RecordNotFound)
      get "#{base_path}/nonexistent", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # CREATE
  # =========================================================================
  describe "POST /api/v1/ai/mcp_apps" do
    let(:path) { base_path }
    let(:valid_params) do
      {
        name: "Test App",
        description: "A test MCP app",
        app_type: "custom",
        status: "draft",
        html_content: "<div>Test</div>"
      }
    end

    before do
      allow(renderer_service).to receive(:create_app).and_return(mcp_app)
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates an app and returns success' do
      post path, params: valid_params.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['app']).to be_present
    end
  end

  # =========================================================================
  # UPDATE
  # =========================================================================
  describe "PATCH /api/v1/ai/mcp_apps/:id" do
    let(:path) { "#{base_path}/#{mcp_app.id}" }
    let(:update_params) { { name: "Updated App" } }

    before do
      allow(renderer_service).to receive(:update_app).and_return(mcp_app)
    end

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'updates the app and returns success' do
      patch path, params: update_params.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['app']).to be_present
    end
  end

  # =========================================================================
  # DESTROY
  # =========================================================================
  describe "DELETE /api/v1/ai/mcp_apps/:id" do
    let(:path) { "#{base_path}/#{mcp_app.id}" }

    before do
      allow(renderer_service).to receive(:delete_app).and_return(true)
    end

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'deletes the app and returns success' do
      delete path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['message']).to include('deleted')
    end

    it 'returns not found for nonexistent app' do
      allow(renderer_service).to receive(:delete_app).and_raise(ActiveRecord::RecordNotFound)
      delete "#{base_path}/nonexistent", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # RENDER APP
  # =========================================================================
  describe "POST /api/v1/ai/mcp_apps/:id/render" do
    let(:path) { "#{base_path}/#{mcp_app.id}/render" }
    let(:mock_instance) { instance_double("Ai::McpAppInstance", id: SecureRandom.uuid) }
    let(:render_result) do
      {
        html: "<div>Rendered</div>",
        instance: mock_instance,
        csp_headers: {},
        sandbox_attrs: "allow-scripts"
      }
    end

    before do
      allow(renderer_service).to receive(:get_app).with(mcp_app.id.to_s).and_return(mcp_app)
      allow(renderer_service).to receive(:render_app).and_return(render_result)
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'renders the app and returns HTML with metadata' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['html']).to eq("<div>Rendered</div>")
      expect(json_response['data']['instance_id']).to be_present
    end
  end

  # =========================================================================
  # PROCESS INPUT
  # =========================================================================
  describe "POST /api/v1/ai/mcp_apps/:id/process" do
    let(:path) { "#{base_path}/#{mcp_app.id}/process" }
    let(:process_params) { { instance_id: SecureRandom.uuid, input_data: { key: "value" } } }
    let(:process_result) do
      { response: { status: "ok" }, state_update: { updated: true } }
    end

    before do
      allow(renderer_service).to receive(:process_user_input).and_return(process_result)
    end

    it 'returns 401 when unauthenticated' do
      post path, params: process_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, params: process_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'processes input and returns response' do
      post path, params: process_params.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['response']).to be_present
      expect(json_response['data']['state_update']).to be_present
    end
  end
end
