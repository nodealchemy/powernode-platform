# frozen_string_literal: true

require 'rails_helper'

# Authorization guard coverage for Api::V1::Ai::TeamChannelMessagesController.
#
# The controller previously ran every action with `authenticate_request` only
# and NO authorization filter — my_channels/messages reads and send_message /
# link / unlink mutations all executed for any authenticated user. These specs
# lock in the gate:
#
#   READ  actions  -> require_any_permission("ai.teams.manage", "ai.teams.execute")
#   WRITE actions  -> require_permission("ai.teams.execute")
#
# Role holdings (see config/permissions.rb): `member` holds ai.teams.manage but
# NOT ai.teams.execute (intended read-only); `manager`/`owner`/`admin` hold both.
RSpec.describe 'Api::V1::Ai::TeamChannelMessagesController authorization', type: :request do
  let(:account) { create(:account) }
  let!(:team) { create(:ai_agent_team, account: account) }
  let!(:channel) { create(:ai_team_channel, agent_team: team) }

  # Representative READ + WRITE endpoints.
  def get_read_my_channels(user)
    get "/api/v1/ai/channels", headers: auth_headers_for(user)
  end

  def get_read_messages(user)
    get "/api/v1/ai/teams/#{team.id}/channels/#{channel.id}/messages", headers: auth_headers_for(user)
  end

  def post_write_send_message(user)
    post "/api/v1/ai/teams/#{team.id}/channels/#{channel.id}/messages",
         params: { content: 'hello' }.to_json,
         headers: auth_headers_for(user)
  end

  def delete_write_unlink(user)
    delete "/api/v1/ai/teams/#{team.id}/channels/#{channel.id}/unlink",
           params: { chat_channel_id: 'missing' }.to_json,
           headers: auth_headers_for(user)
  end

  describe 'user with NO permissions (permissions: [])' do
    let(:user) { create(:user, account: account, permissions: []) }

    it 'is forbidden on a READ action (my_channels)' do
      get_read_my_channels(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a READ action (messages)' do
      get_read_messages(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (send_message)' do
      post_write_send_message(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (unlink_chat_channel)' do
      delete_write_unlink(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user with ONLY ai.teams.manage (member-equivalent, read-only)' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.manage']) }

    it 'is NOT forbidden on a READ action (my_channels)' do
      get_read_my_channels(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a READ action (messages)' do
      get_read_messages(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (send_message) — manage can read but not mutate' do
      post_write_send_message(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (unlink_chat_channel) — manage can read but not mutate' do
      delete_write_unlink(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user with ai.teams.execute' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.execute']) }

    it 'is NOT forbidden on a READ action (messages)' do
      get_read_messages(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a WRITE action (send_message)' do
      post_write_send_message(user)
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
