# frozen_string_literal: true

require 'rails_helper'

# Inbound webhook receivers MUST acknowledge with a 2xx even when post-verification
# PROCESSING fails — a 5xx makes the provider/platform retry-storm (CLAUDE.md high-stakes
# rule; advisory hook webhook-500-check.sh). These specs force a processing error after
# auth/signature has passed and assert the receiver does NOT return 5xx.
#
# Scope: the three CORE-tracked receivers. The payment receivers (stripe/paypal/stripe_sync)
# are business-extension-owned (gitignored in core) and are covered by a spec inside that
# submodule.
RSpec.describe 'Webhook processing-error resilience (core receivers)', type: :request do
  describe 'Api::V1::Webhooks::GitController' do
    let(:account) { create(:account) }
    let(:repo) { create(:git_repository, :with_webhook, account: account) }

    it 'acknowledges 2xx (not 5xx) when event creation raises after a valid signature' do
      allow_any_instance_of(Api::V1::Webhooks::GitController)
        .to receive(:find_repository).and_return(repo)
      allow_any_instance_of(Api::V1::Webhooks::GitController)
        .to receive(:verify_signature).and_return(true)
      allow_any_instance_of(Api::V1::Webhooks::GitController)
        .to receive(:create_webhook_event).and_raise(StandardError, 'boom')

      post '/api/v1/webhooks/git/github',
           params: { repository: { full_name: repo.full_name } }, as: :json

      expect(response.status).not_to eq(500)
      expect(response.status).to be_between(200, 299)
    end
  end

  describe 'Api::V1::Ai::RalphLoopWebhooksController' do
    let(:account) { create(:account) }
    let(:webhook_token) { SecureRandom.urlsafe_base64(32) }
    let!(:ralph_loop) do
      create(:ai_ralph_loop, :pending, account: account,
             scheduling_mode: 'event_triggered', webhook_token: webhook_token)
    end

    it 'acknowledges 2xx (not 5xx) when the execution service raises' do
      allow_any_instance_of(Ai::Ralph::ExecutionService)
        .to receive(:start_loop).and_raise(StandardError, 'boom')

      post "/api/v1/ai/ralph_loops/webhook/#{webhook_token}", as: :json

      expect(response.status).not_to eq(500)
      expect(response.status).to be_between(200, 299)
    end
  end

  describe 'Api::V1::Chat::WebhooksController' do
    let(:account) { create(:account) }
    let(:channel) { create(:chat_channel, account: account) }

    it 'acknowledges 2xx (not 5xx) when the gateway service raises' do
      allow_any_instance_of(::Chat::WebhookVerificationService)
        .to receive(:verify!).and_return(true)
      allow_any_instance_of(::Chat::GatewayService)
        .to receive(:process_webhook).and_raise(StandardError, 'boom')

      post "/api/v1/chat/webhooks/#{channel.webhook_token}", as: :json

      expect(response.status).not_to eq(500)
      expect(response.status).to be_between(200, 299)
    end
  end
end
