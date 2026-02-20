# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP Sessions API", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.agents.read", account: account) }
  let(:headers) { auth_headers_for(user) }

  # ===========================================================================
  # GET /api/v1/mcp/sessions
  # ===========================================================================
  describe "GET /api/v1/mcp/sessions" do
    let(:path) { "/api/v1/mcp/sessions" }

    let!(:session) do
      McpSession.create!(
        user: user,
        account: account,
        protocol_version: "2025-06-18",
        client_info: { "name" => "test-client" }
      )
    end

    it "returns list of account's sessions" do
      get path, headers: headers

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.length).to eq(1)
    end

    it "includes user_name, status, client_info, protocol_version" do
      get path, headers: headers

      expect_success_response
      data = json_response_data
      entry = data.first
      expect(entry["user_name"]).to eq(user.name)
      expect(entry["status"]).to eq("active")
      expect(entry["client_info"]).to eq({ "name" => "test-client" })
      expect(entry["protocol_version"]).to eq("2025-06-18")
    end

    it "filters by status param" do
      revoked_session = McpSession.create!(
        user: user,
        account: account,
        status: "revoked",
        protocol_version: "2025-06-18"
      )

      get "#{path}?status=revoked", headers: headers

      expect_success_response
      data = json_response_data
      ids = data.map { |s| s["id"] }
      expect(ids).to include(revoked_session.id)
      expect(ids).not_to include(session.id)
    end

    it "only returns sessions for current account" do
      other_account = create(:account)
      other_user = create(:user, account: other_account)
      McpSession.create!(user: other_user, account: other_account, protocol_version: "2025-06-18")

      get path, headers: headers

      expect_success_response
      data = json_response_data
      account_ids = data.map { |s| s["user_id"] }
      expect(account_ids).to all(eq(user.id))
    end

    it "requires ai.agents.read permission" do
      user_no_perm = user_with_permissions(account: account)
      get path, headers: auth_headers_for(user_no_perm)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get path, headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # GET /api/v1/mcp/sessions/:id
  # ===========================================================================
  describe "GET /api/v1/mcp/sessions/:id" do
    let!(:session) do
      McpSession.create!(
        user: user,
        account: account,
        protocol_version: "2025-06-18",
        client_info: { "name" => "test-client" }
      )
    end

    it "returns session detail" do
      get "/api/v1/mcp/sessions/#{session.id}", headers: headers

      expect_success_response
      data = json_response_data
      expect(data["id"]).to eq(session.id)
      expect(data["session_token"]).to eq(session.session_token)
      expect(data["protocol_version"]).to eq("2025-06-18")
      expect(data["user_name"]).to eq(user.name)
    end

    it "returns 404 for session from different account" do
      other_account = create(:account)
      other_user = create(:user, account: other_account)
      other_session = McpSession.create!(user: other_user, account: other_account)

      get "/api/v1/mcp/sessions/#{other_session.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires ai.agents.read permission" do
      user_no_perm = user_with_permissions(account: account)
      get "/api/v1/mcp/sessions/#{session.id}", headers: auth_headers_for(user_no_perm)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/mcp/sessions/#{session.id}", headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # DELETE /api/v1/mcp/sessions/:id
  # ===========================================================================
  describe "DELETE /api/v1/mcp/sessions/:id" do
    let!(:session) do
      McpSession.create!(
        user: user,
        account: account,
        protocol_version: "2025-06-18"
      )
    end

    it "revokes session" do
      delete "/api/v1/mcp/sessions/#{session.id}", headers: headers

      expect_success_response
      data = json_response_data
      expect(data["status"]).to eq("revoked")
    end

    it "changes session status to 'revoked'" do
      delete "/api/v1/mcp/sessions/#{session.id}", headers: headers

      expect_success_response
      expect(session.reload.status).to eq("revoked")
    end

    it "returns the session id" do
      delete "/api/v1/mcp/sessions/#{session.id}", headers: headers

      expect_success_response
      data = json_response_data
      expect(data["id"]).to eq(session.id)
    end

    it "returns 404 for session from different account" do
      other_account = create(:account)
      other_user = create(:user, account: other_account)
      other_session = McpSession.create!(user: other_user, account: other_account)

      delete "/api/v1/mcp/sessions/#{other_session.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires ai.agents.read permission" do
      user_no_perm = user_with_permissions(account: account)
      delete "/api/v1/mcp/sessions/#{session.id}", headers: auth_headers_for(user_no_perm)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      delete "/api/v1/mcp/sessions/#{session.id}", headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
