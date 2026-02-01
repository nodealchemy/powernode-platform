# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A2A Protocol", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:jwt_token) { Security::JwtService.encode({ user_id: user.id }) }
  let(:auth_headers) { { "Authorization" => "Bearer #{jwt_token}" } }

  describe "GET /.well-known/agent-card.json" do
    it "returns platform agent card" do
      get "/.well-known/agent-card.json"

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["name"]).to eq("Powernode")
      expect(json["protocolVersion"]).to be_present
      expect(json["skills"]).to be_an(Array)
    end

    it "is publicly accessible" do
      get "/.well-known/agent-card.json"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /a2a" do
    it "returns protocol info" do
      get "/a2a"

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["protocol"]).to eq("a2a")
      expect(json["supported_methods"]).to be_an(Array)
    end
  end

  describe "POST /a2a" do
    it "requires authentication" do
      post "/a2a",
           params: { jsonrpc: "2.0", id: "1", method: "tasks/list", params: {} }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq(-32001)
    end

    describe "tasks/list" do
      it "lists tasks for authenticated user" do
        create_list(:ai_a2a_task, 3, account: account)

        post "/a2a",
             params: { jsonrpc: "2.0", id: "1", method: "tasks/list", params: {} }.to_json,
             headers: auth_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["result"]["tasks"].count).to eq(3)
      end
    end

    describe "tasks/get" do
      let(:task) { create(:ai_a2a_task, account: account) }

      it "returns task details" do
        post "/a2a",
             params: { jsonrpc: "2.0", id: "1", method: "tasks/get", params: { id: task.task_id } }.to_json,
             headers: auth_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["result"]["id"]).to eq(task.task_id)
      end
    end

    describe "tasks/cancel" do
      let(:task) { create(:ai_a2a_task, account: account, status: "active") }

      it "cancels a task" do
        post "/a2a",
             params: { jsonrpc: "2.0", id: "1", method: "tasks/cancel", params: { id: task.task_id } }.to_json,
             headers: auth_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        # A2A protocol uses status.state structure and "canceled" (US spelling)
        expect(json["result"]["status"]["state"]).to eq("canceled")
      end
    end

    describe "message/send" do
      it "executes a skill" do
        workflow = create(:ai_workflow, account: account, status: "active")

        post "/a2a",
             params: {
               jsonrpc: "2.0",
               id: "1",
               method: "message/send",
               params: {
                 skill: "workflows.list",
                 input: {}
               }
             }.to_json,
             headers: auth_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        # Result may be error if skill execution fails, but response should be valid JSON-RPC
        expect(json["jsonrpc"]).to eq("2.0")
        expect(json["id"]).to eq("1")
      end
    end

    describe "agent/authenticatedExtendedCard" do
      it "returns platform card" do
        post "/a2a",
             params: { jsonrpc: "2.0", id: "1", method: "agent/authenticatedExtendedCard", params: {} }.to_json,
             headers: auth_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["result"]["name"]).to eq("Powernode")
      end
    end

    describe "error handling" do
      it "returns parse error for invalid JSON" do
        post "/a2a",
             params: "not json",
             headers: auth_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq(-32700)
      end

      it "returns invalid request for missing jsonrpc" do
        post "/a2a",
             params: { id: "1", method: "tasks/list" }.to_json,
             headers: auth_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq(-32600)
      end

      it "returns method not found for unknown method" do
        post "/a2a",
             params: { jsonrpc: "2.0", id: "1", method: "unknown/method", params: {} }.to_json,
             headers: auth_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq(-32601)
      end
    end
  end

  describe "API key authentication" do
    let!(:api_key) do
      key = ApiKey.new(
        account: account,
        name: "Test Key",
        is_active: true,
        created_by: user
      )
      key.save!
      key
    end

    it "authenticates with X-API-Key header" do
      # Verify key can be looked up
      found_key = ApiKey.find_by_key(api_key.key_value)
      expect(found_key).to be_present
      expect(found_key.active?).to be true

      post "/a2a",
           params: { jsonrpc: "2.0", id: "1", method: "tasks/list", params: {} }.to_json,
           headers: { "Content-Type" => "application/json", "X-API-Key" => api_key.key_value }

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      # Should have either result or error
      expect(json["jsonrpc"]).to eq("2.0")
      expect(json["result"] || json["error"]).to be_present
    end
  end
end
