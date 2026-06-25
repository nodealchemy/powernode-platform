# frozen_string_literal: true

require "rails_helper"

# chat/* controllers (channels, sessions) previously ran on authentication
# alone — no require_permission. Any authenticated user could list/manage chat
# channels (including regenerate_token, which rotates a channel credential) and
# chat sessions. These specs lock in the chat.* permission family:
#   reads  -> chat.<resource>.read
#   writes -> chat.<resource>.manage
# cleanup_sessions is worker-internal (ChatSessionCleanupJob) and must require
# WORKER auth, not a user permission (mirrors ai/teams cleanup_messages).
RSpec.describe "Api::V1::Chat authorization", type: :request do
  let(:account) { create(:account) }
  let(:no_perms) { create(:user, account: account, permissions: [ "user.read" ]) }

  describe "channels" do
    let(:reader)  { create(:user, account: account, permissions: [ "chat.channels.read" ]) }
    let(:manager) { create(:user, account: account, permissions: [ "chat.channels.read", "chat.channels.manage" ]) }
    let!(:channel) { create(:chat_channel, account: account) }

    it "forbids index without chat.channels.read" do
      get "/api/v1/chat/channels", headers: auth_headers_for(no_perms), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "allows index with chat.channels.read" do
      get "/api/v1/chat/channels", headers: auth_headers_for(reader), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end

    it "forbids create without chat.channels.manage (read is not enough)" do
      post "/api/v1/chat/channels",
           params: { channel: { name: "X", platform: "telegram" } },
           headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids regenerate_token (credential rotation) without chat.channels.manage" do
      post "/api/v1/chat/channels/#{channel.id}/regenerate_token",
           headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "allows regenerate_token with chat.channels.manage" do
      post "/api/v1/chat/channels/#{channel.id}/regenerate_token",
           headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  describe "sessions" do
    let(:reader)  { create(:user, account: account, permissions: [ "chat.sessions.read" ]) }
    let(:manager) { create(:user, account: account, permissions: [ "chat.sessions.read", "chat.sessions.manage" ]) }
    let(:channel) { create(:chat_channel, account: account) }
    let!(:session) { create(:chat_session, channel: channel) }

    it "forbids index without chat.sessions.read" do
      get "/api/v1/chat/sessions", headers: auth_headers_for(no_perms), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "allows index with chat.sessions.read" do
      get "/api/v1/chat/sessions", headers: auth_headers_for(reader), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end

    it "forbids close without chat.sessions.manage (read is not enough)" do
      post "/api/v1/chat/sessions/#{session.id}/close",
           headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "allows close with chat.sessions.manage" do
      post "/api/v1/chat/sessions/#{session.id}/close",
           headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  describe "cleanup_sessions (worker-internal)" do
    let(:privileged) do
      create(:user, account: account, permissions: [ "chat.channels.read", "chat.channels.manage" ])
    end
    let(:worker) { create(:worker, account: account) }

    def worker_headers(w)
      payload = {
        sub: w.id,
        account_id: w.account_id,
        type: "worker",
        permissions: w.permission_names,
        version: Security::JwtService::CURRENT_TOKEN_VERSION
      }
      { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
    end

    it "forbids a user token (even one holding chat.channels.manage)" do
      post "/api/v1/chat/channels/cleanup_sessions", headers: auth_headers_for(privileged), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "allows a worker token (the scheduled cleanup job)" do
      post "/api/v1/chat/channels/cleanup_sessions", headers: worker_headers(worker), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
