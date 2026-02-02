# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat Webhooks API', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:chat_channel, :telegram, :connected, account: account) }

  describe 'POST /api/v1/chat/webhooks/:token' do
    let(:telegram_payload) do
      {
        update_id: 123456789,
        message: {
          message_id: 1,
          from: {
            id: 123456,
            first_name: 'Test',
            username: 'testuser'
          },
          chat: {
            id: 123456,
            type: 'private'
          },
          date: Time.current.to_i,
          text: 'Hello!'
        }
      }
    end

    before do
      allow_any_instance_of(Chat::WebhookVerificationService).to receive(:verify!).and_return(true)
      allow_any_instance_of(Chat::GatewayService).to receive(:process_webhook).and_return({ success: true })
    end

    it 'processes valid webhook' do
      post "/api/v1/chat/webhooks/#{channel.webhook_token}",
           params: telegram_payload.to_json,
           headers: { 'Content-Type' => 'application/json', 'X-Telegram-Bot-Api-Secret-Token' => 'test' }

      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 for invalid token' do
      post '/api/v1/chat/webhooks/invalid_token',
           params: telegram_payload.to_json,
           headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 429 when rate limited' do
      allow_any_instance_of(Security::RateLimiter).to receive(:exceeded?).and_return(true)

      post "/api/v1/chat/webhooks/#{channel.webhook_token}",
           params: telegram_payload.to_json,
           headers: { 'Content-Type' => 'application/json', 'X-Telegram-Bot-Api-Secret-Token' => 'test' }

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'GET /api/v1/chat/webhooks/:token/verify' do
    context 'Telegram verification' do
      it 'returns 200 for valid telegram channel' do
        get "/api/v1/chat/webhooks/#{channel.webhook_token}/verify",
            headers: { 'X-Telegram-Bot-Api-Secret-Token' => channel.webhook_token }

        expect(response).to have_http_status(:ok)
      end
    end

    context 'WhatsApp verification' do
      let(:whatsapp_channel) { create(:chat_channel, :whatsapp, :connected, account: account) }

      it 'returns challenge for valid verification request' do
        get "/api/v1/chat/webhooks/#{whatsapp_channel.webhook_token}/verify",
            params: {
              'hub.mode' => 'subscribe',
              'hub.challenge' => '12345',
              'hub.verify_token' => whatsapp_channel.webhook_token
            }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq('12345')
      end
    end

    context 'Slack verification' do
      let(:slack_channel) { create(:chat_channel, :slack, :connected, account: account) }

      it 'echoes challenge for url_verification' do
        post "/api/v1/chat/webhooks/#{slack_channel.webhook_token}",
             params: { type: 'url_verification', challenge: 'test_challenge' }.to_json,
             headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['challenge']).to eq('test_challenge')
      end
    end

    context 'Discord verification' do
      let(:discord_channel) { create(:chat_channel, :discord, :connected, account: account) }

      before do
        allow_any_instance_of(Chat::WebhookVerificationService).to receive(:verify!).and_return(true)
      end

      it 'handles PING interaction' do
        post "/api/v1/chat/webhooks/#{discord_channel.webhook_token}",
             params: { type: 1 }.to_json,
             headers: {
               'Content-Type' => 'application/json',
               'X-Signature-Ed25519' => 'valid_signature',
               'X-Signature-Timestamp' => Time.current.to_i.to_s
             }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['type']).to eq(1)
      end
    end

    it 'returns 404 for invalid token' do
      get '/api/v1/chat/webhooks/invalid_token/verify'

      expect(response).to have_http_status(:not_found)
    end
  end
end
