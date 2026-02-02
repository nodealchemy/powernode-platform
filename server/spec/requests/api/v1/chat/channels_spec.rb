# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat Channels API', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :admin, account: account) }
  let(:headers) { auth_headers(user) }

  describe 'GET /api/v1/chat/channels' do
    let!(:telegram_channel) { create(:chat_channel, :telegram, :connected, account: account) }
    let!(:discord_channel) { create(:chat_channel, :discord, :disconnected, account: account) }
    let!(:other_account_channel) { create(:chat_channel) }

    it 'returns list of channels for the account' do
      get '/api/v1/chat/channels', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['items'].length).to eq(2)
      expect(json_response['items'].map { |c| c['id'] }).to contain_exactly(telegram_channel.id, discord_channel.id)
    end

    it 'filters by platform' do
      get '/api/v1/chat/channels', params: { platform: 'telegram' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['items'].length).to eq(1)
      expect(json_response['items'].first['platform']).to eq('telegram')
    end

    it 'filters by status' do
      get '/api/v1/chat/channels', params: { status: 'connected' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['items'].length).to eq(1)
      expect(json_response['items'].first['status']).to eq('connected')
    end

    it 'requires authentication' do
      get '/api/v1/chat/channels'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/chat/channels/:id' do
    let!(:channel) { create(:chat_channel, :telegram, account: account) }

    it 'returns channel details' do
      get "/api/v1/chat/channels/#{channel.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['channel']['id']).to eq(channel.id)
      expect(json_response['channel']['name']).to eq(channel.name)
    end

    it 'returns 404 for non-existent channel' do
      get "/api/v1/chat/channels/#{SecureRandom.uuid}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for channel from another account' do
      other_channel = create(:chat_channel)
      get "/api/v1/chat/channels/#{other_channel.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/chat/channels' do
    let(:valid_params) do
      {
        channel: {
          name: 'My Telegram Bot',
          platform: 'telegram',
          rate_limit_per_minute: 60
        }
      }
    end

    it 'creates a new channel' do
      expect {
        post '/api/v1/chat/channels', params: valid_params, headers: headers
      }.to change(Chat::Channel, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response['channel']['name']).to eq('My Telegram Bot')
      expect(json_response['channel']['platform']).to eq('telegram')
    end

    it 'validates required fields' do
      post '/api/v1/chat/channels', params: { channel: { name: '' } }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'validates platform is supported' do
      post '/api/v1/chat/channels', params: { channel: { name: 'Test', platform: 'invalid' } }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/chat/channels/:id' do
    let!(:channel) { create(:chat_channel, :telegram, account: account) }

    it 'updates the channel' do
      patch "/api/v1/chat/channels/#{channel.id}",
            params: { channel: { name: 'Updated Name' } },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['channel']['name']).to eq('Updated Name')
      expect(channel.reload.name).to eq('Updated Name')
    end

    it 'validates updates' do
      patch "/api/v1/chat/channels/#{channel.id}",
            params: { channel: { rate_limit_per_minute: 2000 } },
            headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/chat/channels/:id' do
    let!(:channel) { create(:chat_channel, :telegram, account: account) }

    it 'deletes the channel' do
      expect {
        delete "/api/v1/chat/channels/#{channel.id}", headers: headers
      }.to change(Chat::Channel, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /api/v1/chat/channels/:id/connect' do
    let!(:channel) { create(:chat_channel, :telegram, :disconnected, account: account) }

    before do
      allow_any_instance_of(Chat::GatewayService).to receive(:connect_channel).and_return({ success: true })
    end

    it 'connects the channel' do
      post "/api/v1/chat/channels/#{channel.id}/connect", headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /api/v1/chat/channels/:id/disconnect' do
    let!(:channel) { create(:chat_channel, :telegram, :connected, account: account) }

    it 'disconnects the channel' do
      post "/api/v1/chat/channels/#{channel.id}/disconnect", headers: headers

      expect(response).to have_http_status(:ok)
      expect(channel.reload.status).to eq('disconnected')
    end
  end

  describe 'POST /api/v1/chat/channels/:id/regenerate_token' do
    let!(:channel) { create(:chat_channel, :telegram, account: account) }
    let(:old_token) { channel.webhook_token }

    it 'regenerates the webhook token' do
      post "/api/v1/chat/channels/#{channel.id}/regenerate_token", headers: headers

      expect(response).to have_http_status(:ok)
      expect(channel.reload.webhook_token).not_to eq(old_token)
      expect(json_response['webhook_url']).to include(channel.reload.webhook_token)
    end
  end

  describe 'GET /api/v1/chat/channels/:id/sessions' do
    let!(:channel) { create(:chat_channel, :telegram, account: account) }
    let!(:active_session) { create(:chat_session, :active, channel: channel) }
    let!(:closed_session) { create(:chat_session, :closed, channel: channel) }

    it 'returns channel sessions' do
      get "/api/v1/chat/channels/#{channel.id}/sessions", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['items'].length).to eq(2)
    end

    it 'filters by status' do
      get "/api/v1/chat/channels/#{channel.id}/sessions", params: { status: 'active' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['items'].length).to eq(1)
      expect(json_response['items'].first['status']).to eq('active')
    end
  end

  describe 'GET /api/v1/chat/channels/:id/metrics' do
    let!(:channel) { create(:chat_channel, :telegram, :with_sessions, account: account) }

    it 'returns channel metrics' do
      get "/api/v1/chat/channels/#{channel.id}/metrics", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['metrics']).to include('total_sessions', 'active_sessions', 'status')
    end
  end

  describe 'GET /api/v1/chat/channels/platforms' do
    it 'returns list of supported platforms' do
      get '/api/v1/chat/channels/platforms', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['platforms'].map { |p| p['id'] }).to include('telegram', 'discord', 'slack', 'whatsapp', 'mattermost')
    end
  end
end
