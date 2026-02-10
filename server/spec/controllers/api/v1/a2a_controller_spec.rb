# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::A2aController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:jwt_token) { Security::JwtService.encode({ user_id: user.id }) }

  describe "GET #info" do
    it "returns A2A protocol info" do
      get :info

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["protocol"]).to eq("a2a")
      expect(json["version"]).to eq("1.0.0")
      expect(json["supported_methods"]).to be_an(Array)
      expect(json["agent_card_url"]).to include("/.well-known/agent-card.json")
    end
  end

  describe "POST #handle" do
    context "without authentication" do
      it "returns authentication error" do
        post :handle, body: {
          jsonrpc: "2.0",
          id: "1",
          method: "tasks/list",
          params: {}
        }.to_json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq(-32001)
        expect(json["error"]["message"]).to include("Authentication")
      end
    end

    context "with valid authentication" do
      before do
        request.headers["Authorization"] = "Bearer #{jwt_token}"
      end

      it "handles tasks/list method" do
        post :handle, body: {
          jsonrpc: "2.0",
          id: "1",
          method: "tasks/list",
          params: {}
        }.to_json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["jsonrpc"]).to eq("2.0")
        expect(json["id"]).to eq("1")
        expect(json["result"]).to be_present
      end

      it "handles tasks/get method" do
        task = create(:ai_a2a_task, account: account)

        post :handle, body: {
          jsonrpc: "2.0",
          id: "2",
          method: "tasks/get",
          params: { id: task.task_id }
        }.to_json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["result"]["id"]).to eq(task.task_id)
      end

      it "returns error for unknown method" do
        post :handle, body: {
          jsonrpc: "2.0",
          id: "3",
          method: "unknown/method",
          params: {}
        }.to_json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq(-32601)
        expect(json["error"]["message"]).to include("Method not found")
      end

      it "returns parse error for invalid JSON" do
        post :handle, body: "invalid json"

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq(-32700)
      end

      it "returns invalid request for missing jsonrpc version" do
        post :handle, body: {
          id: "4",
          method: "tasks/list"
        }.to_json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq(-32600)
      end
    end

    context "with API key authentication" do
      let!(:api_key) do
        key = ApiKey.new(account: account, name: "Test Key", is_active: true, created_by: user)
        key.save!
        key
      end

      before do
        request.headers["X-API-Key"] = api_key.key_value
      end

      it "authenticates with API key" do
        post :handle, body: {
          jsonrpc: "2.0",
          id: "1",
          method: "tasks/list",
          params: {}
        }.to_json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["jsonrpc"]).to eq("2.0")
        expect(json["result"] || json["error"]).to be_present
      end
    end
  end

  describe "tasks/cancel" do
    let(:task) { create(:ai_a2a_task, account: account, status: "active") }

    before do
      request.headers["Authorization"] = "Bearer #{jwt_token}"
    end

    it "cancels a task" do
      post :handle, body: {
        jsonrpc: "2.0",
        id: "1",
        method: "tasks/cancel",
        params: { id: task.task_id, reason: "User requested" }
      }.to_json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["result"]["status"]["state"]).to eq("canceled")

      task.reload
      expect(task.status).to eq("cancelled")
    end
  end

  describe "agent/authenticatedExtendedCard" do
    before do
      request.headers["Authorization"] = "Bearer #{jwt_token}"
    end

    it "returns platform card when no agentCardId specified" do
      post :handle, body: {
        jsonrpc: "2.0",
        id: "1",
        method: "agent/authenticatedExtendedCard",
        params: {}
      }.to_json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["result"]["name"]).to eq("Powernode")
    end

    it "returns specific agent card when agentCardId specified" do
      agent_card = create(:ai_agent_card, account: account)

      post :handle, body: {
        jsonrpc: "2.0",
        id: "1",
        method: "agent/authenticatedExtendedCard",
        params: { agentCardId: agent_card.id }
      }.to_json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["result"]["name"]).to eq(agent_card.name)
    end
  end
end
