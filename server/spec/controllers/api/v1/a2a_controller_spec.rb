# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::A2aController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:jwt_token) { Security::JwtService.encode({ user_id: user.id }) }

  # IMP-01a07d5a. authenticate_jwt_token resolved a real User and then returned
  # `user&.account`, discarding the identity it had just proved. Every skill
  # therefore ran with user: nil, and A2a::Skills::MemorySkills#authorize! —
  # which exists, is parameterised per skill, and returns early on a nil user —
  # could never refuse anything. Its own comment said so: "@user is nil on
  # every production path today, so this check is currently INERT ... when the
  # user is threaded through, this starts refusing without further change."
  #
  # The assertion is on what the SKILL LAYER receives, not on a response body:
  # the defect is an identity dropped at the boundary, and a skill that happens
  # to succeed without a user looks identical either way.
  describe "the authenticated identity reaching the skill layer" do
    let(:handler) { instance_double(A2a::MessageHandler, list_tasks: { result: { tasks: [] } }) }

    def post_tasks_list
      post :handle, body: {
        jsonrpc: "2.0", id: "1", method: "tasks/list", params: {}
      }.to_json
    end

    it "hands the JWT's user to the handler, not only its account" do
      request.headers["Authorization"] = "Bearer #{jwt_token}"

      expect(A2a::MessageHandler).to receive(:new)
        .with(account: account, user: user).and_return(handler)

      post_tasks_list

      expect(response).to have_http_status(:ok)
    end

    it "hands the same identity to the streaming endpoint" do
      request.headers["Authorization"] = "Bearer #{jwt_token}"
      streaming = instance_double(A2a::MessageHandler)
      allow(streaming).to receive(:stream_message)

      expect(A2a::MessageHandler).to receive(:new)
        .with(account: account, user: user).and_return(streaming)

      post :stream, body: { jsonrpc: "2.0", id: "1", params: {} }.to_json
    end

    # An ApiKey belongs to an account and has SCOPES; it has no owning user, so
    # there is no identity to thread and the skill-side permission check stays
    # inert on this path. Pinned rather than left implicit: the asymmetry is
    # deliberate, and inferring a user from an account here would be the
    # invented-identity mistake in the other direction. Gating this path on the
    # key's own scopes is a separate question, and a separate change.
    it "passes no user for an API-key principal, which has none" do
      api_key = ApiKey.new(account: account, name: "A2A Key", is_active: true, created_by: user)
      api_key.save!
      request.headers["X-API-Key"] = api_key.key_value

      expect(A2a::MessageHandler).to receive(:new)
        .with(account: account, user: nil).and_return(handler)

      post_tasks_list
    end

    # A token naming a user who no longer exists must not authenticate as the
    # account anyway. Before the fix `user&.account` returned nil here and the
    # request was refused for the right reason by accident; the refusal is now
    # the explicit one.
    it "refuses a token whose user is gone" do
      token = Security::JwtService.encode({ user_id: SecureRandom.uuid })
      request.headers["Authorization"] = "Bearer #{token}"

      post_tasks_list

      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq(-32001)
    end
  end

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

      # THIS EXAMPLE IS WHY THE BREAKAGE SURVIVED. It used to assert
      # `json["result"] || json["error"]` — satisfied by the
      # "Authentication required" error body it was meant to rule out, so it
      # passed for as long as API-key authentication had never once worked
      # (IMP-01a07d5a). An oracle that accepts both outcomes tests nothing.
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
        expect(json["error"]).to be_nil
        expect(json["result"]).to be_present
      end

      it "records the usage row with the status the response actually carried" do
        expect {
          post :handle, body: {
            jsonrpc: "2.0", id: "1", method: "tasks/list", params: {}
          }.to_json
        }.to change(ApiKeyUsage, :count).by(1)

        usage = ApiKeyUsage.order(:created_at).last
        expect(usage.api_key).to eq(api_key)
        expect(usage.endpoint).to eq("/api/v1/a2a")
        expect(usage.response_status).to eq(200)
      end

      # Bookkeeping must not be able to reject a valid key. Recording used to
      # sit INSIDE the authenticator, under a rescue that returned nil, so any
      # failure there presented to the caller as an authentication failure.
      it "serves the request even when usage recording fails" do
        allow_any_instance_of(ApiKey).to receive(:record_usage!)
          .and_raise(ActiveRecord::RecordInvalid.new(ApiKeyUsage.new))

        post :handle, body: {
          jsonrpc: "2.0", id: "1", method: "tasks/list", params: {}
        }.to_json

        json = JSON.parse(response.body)
        expect(json["error"]).to be_nil
        expect(json["result"]).to be_present
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
