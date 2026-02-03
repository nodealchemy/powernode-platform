# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat Sessions API', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :admin, account: account) }
  let(:headers) { auth_headers(user) }
  let(:channel) { create(:chat_channel, :telegram, :connected, account: account) }

  describe 'GET /api/v1/chat/sessions' do
    let!(:active_session) { create(:chat_session, :active, channel: channel) }
    let!(:idle_session) { create(:chat_session, :idle, channel: channel) }
    let!(:other_account_session) { create(:chat_session) }

    it 'returns list of sessions for the account' do
      get '/api/v1/chat/sessions', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['items'].length).to eq(2)
    end

    it 'filters by status' do
      get '/api/v1/chat/sessions', params: { status: 'active' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['items'].length).to eq(1)
      expect(json_response['data']['items'].first['status']).to eq('active')
    end

    it 'filters by channel' do
      other_channel = create(:chat_channel, account: account)
      create(:chat_session, channel: other_channel)

      get '/api/v1/chat/sessions', params: { channel_id: channel.id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['items'].length).to eq(2)
    end
  end

  describe 'GET /api/v1/chat/sessions/:id' do
    let!(:session) { create(:chat_session, :with_messages, channel: channel) }

    it 'returns session details' do
      get "/api/v1/chat/sessions/#{session.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['session']['id']).to eq(session.id)
    end

    it 'returns 404 for session from another account' do
      other_session = create(:chat_session)
      get "/api/v1/chat/sessions/#{other_session.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/chat/sessions/:id/transfer' do
    let!(:session) { create(:chat_session, :active, channel: channel) }
    let(:agent) { create(:ai_agent, account: account) }

    it 'transfers session to another agent' do
      post "/api/v1/chat/sessions/#{session.id}/transfer",
           params: { agent_id: agent.id },
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(session.reload.assigned_agent_id).to eq(agent.id)
    end
  end

  describe 'POST /api/v1/chat/sessions/:id/close' do
    let!(:session) { create(:chat_session, :active, channel: channel) }

    it 'closes the session' do
      post "/api/v1/chat/sessions/#{session.id}/close", headers: headers

      expect(response).to have_http_status(:ok)
      expect(session.reload.status).to eq('closed')
    end
  end

  describe 'GET /api/v1/chat/sessions/:id/messages' do
    let!(:session) { create(:chat_session, :with_messages, channel: channel) }

    it 'returns session messages' do
      get "/api/v1/chat/sessions/#{session.id}/messages", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['items'].length).to eq(session.messages.count)
    end

    it 'filters by direction' do
      get "/api/v1/chat/sessions/#{session.id}/messages",
          params: { direction: 'inbound' },
          headers: headers

      expect(response).to have_http_status(:ok)
      json_response['data']['items'].each do |message|
        expect(message['direction']).to eq('inbound')
      end
    end
  end

  describe 'POST /api/v1/chat/sessions/:id/messages' do
    let!(:session) { create(:chat_session, :active, channel: channel) }

    before do
      allow_any_instance_of(Chat::MessageRouter).to receive(:send_outbound).and_return({ success: true })
    end

    it 'sends a message to the session' do
      post "/api/v1/chat/sessions/#{session.id}/messages",
           params: { content: 'Hello from agent!', message_type: 'text' },
           headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /api/v1/chat/sessions/active' do
    let!(:active_sessions) { create_list(:chat_session, 3, :active, channel: channel) }
    let!(:closed_session) { create(:chat_session, :closed, channel: channel) }

    it 'returns only active sessions' do
      get '/api/v1/chat/sessions/active', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['items'].length).to eq(3)
      json_response['data']['items'].each do |session|
        expect(session['status']).to eq('active')
      end
    end
  end

  describe 'GET /api/v1/chat/sessions/stats' do
    let!(:active_sessions) { create_list(:chat_session, 3, :active, channel: channel) }
    let!(:idle_sessions) { create_list(:chat_session, 2, :idle, channel: channel) }
    let!(:closed_session) { create(:chat_session, :closed, channel: channel) }

    it 'returns session statistics' do
      get '/api/v1/chat/sessions/stats', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['stats']).to include('active', 'idle', 'closed', 'total')
      expect(json_response['data']['stats']['active']).to eq(3)
      expect(json_response['data']['stats']['idle']).to eq(2)
    end
  end
end
