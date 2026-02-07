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
      allow(Security::RateLimiter).to receive(:check!).and_raise(
        Security::RateLimiter::RateLimitExceeded.new(limit: 10, window: 60, retry_after: 60)
      )

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
      let(:whatsapp_channel) do
        create(:chat_channel, :whatsapp, :connected, account: account,
               configuration: { 'auto_respond' => true, 'phone_number_id' => '123456789', 'verify_token' => 'wa_verify_secret' })
      end

      it 'returns challenge for valid verification request' do
        get "/api/v1/chat/webhooks/#{whatsapp_channel.webhook_token}/verify",
            params: {
              'hub.mode' => 'subscribe',
              'hub.challenge' => '12345',
              'hub.verify_token' => 'wa_verify_secret'
            }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq('12345')
      end
    end

    context 'Slack verification' do
      let(:slack_channel) { create(:chat_channel, :slack, :connected, account: account) }

      it 'echoes challenge for url_verification' do
        get "/api/v1/chat/webhooks/#{slack_channel.webhook_token}/verify",
            params: { challenge: 'test_challenge' }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['challenge']).to eq('test_challenge')
      end
    end

    context 'Discord verification' do
      let(:discord_channel) { create(:chat_channel, :discord, :connected, account: account) }

      it 'returns ok for valid discord channel' do
        get "/api/v1/chat/webhooks/#{discord_channel.webhook_token}/verify"

        expect(response).to have_http_status(:ok)
      end
    end

    it 'returns 404 for invalid token' do
      get '/api/v1/chat/webhooks/invalid_token/verify'

      expect(response).to have_http_status(:not_found)
    end
  end
end
