# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AI Concierge Conversations", type: :request do
  include PermissionTestHelpers

  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.conversations.create", "ai.conversations.read", "ai.conversations.update", account: account) }
  let(:headers) { auth_headers_for(user) }
  let(:provider) { create(:ai_provider, provider_type: "openai") }
  let(:credential) { create(:ai_provider_credential, provider: provider, account: account, is_active: true) }
  let(:concierge_agent) do
    create(:ai_agent, account: account, provider: provider, is_concierge: true, status: "active", name: "Powernode Assistant")
  end

  before { credential }

  describe "POST /api/v1/ai/conversations/concierge" do
    context "with a concierge agent configured" do
      before { concierge_agent }

      it "creates a new concierge conversation" do
        post "/api/v1/ai/conversations/concierge", headers: headers

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data["conversation"]).to be_present
        expect(data["conversation"]["ai_agent"]["name"]).to eq("Powernode Assistant")
        expect(data["conversation"]["status"]).to eq("active")
      end

      it "returns existing active conversation if one exists" do
        existing = create(:ai_conversation,
          account: account, user: user, agent: concierge_agent,
          provider: provider, status: "active", last_activity_at: Time.current
        )

        post "/api/v1/ai/conversations/concierge", headers: headers

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data["conversation"]["id"]).to eq(existing.id)
      end

      it "creates a new conversation when existing is archived" do
        create(:ai_conversation, :archived,
          account: account, user: user, agent: concierge_agent, provider: provider
        )

        post "/api/v1/ai/conversations/concierge", headers: headers

        expect(response).to have_http_status(:ok)
        # Should create a new one since archived != active
        expect(account.ai_conversations.active.where(ai_agent_id: concierge_agent.id).count).to eq(1)
      end
    end

    context "without a concierge agent" do
      it "returns not found" do
        post "/api/v1/ai/conversations/concierge", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(json_response["error"]).to include("No concierge agent configured")
      end
    end

    context "without permission" do
      let(:user) { user_with_permissions(account: account) }

      it "returns forbidden" do
        concierge_agent

        post "/api/v1/ai/conversations/concierge", headers: headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/ai/conversations/:id/confirm_action" do
    let(:conversation) do
      create(:ai_conversation, account: account, user: user, agent: concierge_agent, provider: provider, status: "active")
    end

    before { concierge_agent }

    it "executes a confirmed action" do
      allow_any_instance_of(Ai::ConciergeService).to receive(:handle_confirmed_action)

      post "/api/v1/ai/conversations/#{conversation.id}/confirm_action",
        params: { action_type: "check_status", action_params: {} }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response_data["confirmed"]).to be true
    end

    it "rejects non-concierge conversations" do
      regular_agent = create(:ai_agent, account: account, provider: provider, is_concierge: false)
      regular_conv = create(:ai_conversation, account: account, user: user, agent: regular_agent, provider: provider, status: "active")

      post "/api/v1/ai/conversations/#{regular_conv.id}/confirm_action",
        params: { action_type: "check_status" }.to_json,
        headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("only available for concierge")
    end

    it "returns not found for missing conversation" do
      post "/api/v1/ai/conversations/nonexistent-id/confirm_action",
        params: { action_type: "check_status" }.to_json,
        headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Concierge routing in send_message" do
    let(:conversation) do
      create(:ai_conversation, account: account, user: user, agent: concierge_agent, provider: provider, status: "active")
    end

    before do
      concierge_agent
      allow_any_instance_of(Ai::ConciergeService).to receive(:process_message)
    end

    it "routes through ConciergeService for concierge agent conversations" do
      expect_any_instance_of(Ai::ConciergeService).to receive(:process_message).with("Hello assistant")

      post "/api/v1/ai/agents/#{concierge_agent.id}/conversations/#{conversation.id}/send_message",
        params: { message: { content: "Hello assistant" } }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      data = json_response_data
      expect(data["concierge_routed"]).to be true
      expect(data["user_message"]).to be_present
    end

    it "does not route regular agent conversations through concierge" do
      regular_agent = create(:ai_agent, account: account, provider: provider, is_concierge: false)
      regular_conv = create(:ai_conversation, account: account, user: user, agent: regular_agent, provider: provider, status: "active")

      # Mock the AI response for regular agent path
      allow_any_instance_of(Api::V1::Ai::ConversationsController).to receive(:generate_ai_response).and_return({
        success: true, content: "Regular response", model: "test", finish_reason: "stop", usage: { total_tokens: 10 }
      })

      post "/api/v1/ai/agents/#{regular_agent.id}/conversations/#{regular_conv.id}/send_message",
        params: { message: { content: "Hello regular agent" } }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      data = json_response_data
      expect(data["concierge_routed"]).to be_nil
    end
  end
end
