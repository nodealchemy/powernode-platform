# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::McpApps", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ["ai.agents.read"]) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/ai/mcp_apps" do
    before do
      create(:ai_mcp_app, :draft, account: account, name: "App One")
      create(:ai_mcp_app, :published, account: account, name: "App Two")
    end

    it "returns all apps for the account" do
      get "/api/v1/ai/mcp_apps", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["apps"].length).to eq(2)
    end

    it "filters by status" do
      get "/api/v1/ai/mcp_apps?status=published", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["apps"].length).to eq(1)
      expect(data["apps"].first["name"]).to eq("App Two")
    end

    it "filters by app_type" do
      create(:ai_mcp_app, :template, account: account, name: "Template App")
      get "/api/v1/ai/mcp_apps?app_type=template", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["apps"].length).to eq(1)
      expect(data["apps"].first["name"]).to eq("Template App")
    end

    context "without permission" do
      let(:no_perm_user) { create(:user, account: account, permissions: []) }
      let(:no_perm_headers) { auth_headers_for(no_perm_user) }

      it "returns forbidden" do
        get "/api/v1/ai/mcp_apps", headers: no_perm_headers, as: :json

        expect_error_response("Permission denied: ai.agents.read", 403)
      end
    end
  end

  describe "GET /api/v1/ai/mcp_apps/:id" do
    let(:mcp_app) { create(:ai_mcp_app, account: account) }

    it "returns the app with detailed fields" do
      get "/api/v1/ai/mcp_apps/#{mcp_app.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["app"]["id"]).to eq(mcp_app.id)
      expect(data["app"]["name"]).to eq(mcp_app.name)
      expect(data["app"]).to have_key("html_content")
      expect(data["app"]).to have_key("csp_policy")
    end

    it "returns 404 for unknown app" do
      get "/api/v1/ai/mcp_apps/#{SecureRandom.uuid}", headers: headers, as: :json

      expect_error_response("MCP App not found", 404)
    end
  end

  describe "POST /api/v1/ai/mcp_apps" do
    it "creates a new MCP app" do
      post "/api/v1/ai/mcp_apps",
           params: {
             name: "New App",
             description: "A test app",
             html_content: "<div>Hello</div>",
             app_type: "custom"
           }.to_json,
           headers: headers

      expect_success_response
      data = json_response_data
      expect(data["app"]["name"]).to eq("New App")
      expect(data["app"]["status"]).to eq("draft")
    end

    it "returns validation error for missing name" do
      post "/api/v1/ai/mcp_apps",
           params: { description: "No name" }.to_json,
           headers: headers

      expect(response.status).to be >= 400
    end

    it "returns validation error for duplicate name in same account" do
      create(:ai_mcp_app, account: account, name: "Duplicate")

      post "/api/v1/ai/mcp_apps",
           params: { name: "Duplicate", html_content: "<div>X</div>" }.to_json,
           headers: headers

      expect(response.status).to be >= 400
    end
  end

  describe "PATCH /api/v1/ai/mcp_apps/:id" do
    let(:mcp_app) { create(:ai_mcp_app, account: account) }

    it "updates the app" do
      patch "/api/v1/ai/mcp_apps/#{mcp_app.id}",
            params: { name: "Updated Name" }.to_json,
            headers: headers

      expect_success_response
      data = json_response_data
      expect(data["app"]["name"]).to eq("Updated Name")
    end

    it "returns 404 for unknown app" do
      patch "/api/v1/ai/mcp_apps/#{SecureRandom.uuid}",
            params: { name: "X" }.to_json,
            headers: headers

      expect_error_response("MCP App not found", 404)
    end
  end

  describe "DELETE /api/v1/ai/mcp_apps/:id" do
    let!(:mcp_app) { create(:ai_mcp_app, account: account) }

    it "deletes the app" do
      delete "/api/v1/ai/mcp_apps/#{mcp_app.id}", headers: headers, as: :json

      expect_success_response
      expect { Ai::McpApp.find(mcp_app.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "returns 404 for unknown app" do
      delete "/api/v1/ai/mcp_apps/#{SecureRandom.uuid}", headers: headers, as: :json

      expect_error_response("MCP App not found", 404)
    end
  end

  describe "POST /api/v1/ai/mcp_apps/:id/render" do
    let(:mcp_app) { create(:ai_mcp_app, account: account, html_content: "<div>Hello {{name}}</div>") }

    it "renders the app with context" do
      post "/api/v1/ai/mcp_apps/#{mcp_app.id}/render",
           params: { context: { name: "World" } }.to_json,
           headers: headers

      expect_success_response
      data = json_response_data
      expect(data["html"]).to include("Hello World")
      expect(data["instance_id"]).to be_present
      expect(data["csp_headers"]).to be_present
    end

    it "returns 404 for unknown app" do
      post "/api/v1/ai/mcp_apps/#{SecureRandom.uuid}/render",
           params: { context: {} }.to_json,
           headers: headers

      expect_error_response("MCP App not found", 404)
    end
  end

  describe "POST /api/v1/ai/mcp_apps/:id/process" do
    let(:mcp_app) { create(:ai_mcp_app, :with_schema, account: account) }
    let(:instance) { create(:ai_mcp_app_instance, mcp_app: mcp_app, account: account) }

    it "processes user input" do
      post "/api/v1/ai/mcp_apps/#{mcp_app.id}/process",
           params: {
             instance_id: instance.id,
             input_data: { "name" => "Test" }
           }.to_json,
           headers: headers

      expect_success_response
      data = json_response_data
      expect(data["response"]["received"]).to be true
    end

    it "returns validation error for invalid input" do
      post "/api/v1/ai/mcp_apps/#{mcp_app.id}/process",
           params: {
             instance_id: instance.id,
             input_data: {}
           }.to_json,
           headers: headers

      expect_success_response
      data = json_response_data
      expect(data["response"]["error"]).to eq("Invalid input")
    end

    it "returns 404 for unknown instance" do
      post "/api/v1/ai/mcp_apps/#{mcp_app.id}/process",
           params: {
             instance_id: SecureRandom.uuid,
             input_data: { "name" => "Test" }
           }.to_json,
           headers: headers

      expect(response.status).to be >= 400
    end
  end
end
