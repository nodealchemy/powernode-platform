# frozen_string_literal: true

require 'rails_helper'

# Internal API for webhook delivery outcome reporting (worker callback).
# The worker PATCHes the delivery outcome here; the *scheduling* of the next
# retry (the Rails API runs no Sidekiq) must honor the endpoint's CONFIGURED
# retry_backoff, not a flat default.
RSpec.describe 'Api::V1::Internal::WebhookDeliveries', type: :request do
  let(:account) { create(:account) }
  let(:webhook_event) { create(:webhook_event, account: account) }

  # Worker mTLS authentication via InternalBaseController.
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  describe 'PATCH /api/v1/internal/webhook_deliveries/:id (failed outcome)' do
    let(:endpoint) do
      create(:webhook_endpoint, account: account, retry_backoff: backoff, retry_limit: 3)
    end
    let(:delivery) do
      create(:webhook_delivery,
             webhook_endpoint: endpoint,
             webhook_event: webhook_event,
             status: 'pending',
             attempt_number: 1)
    end

    def report_failure!
      patch api_v1_internal_webhook_delivery_path(delivery),
            params: { status: 'failed', metadata: { status_code: 500, error_message: 'boom' } },
            headers: internal_headers
    end

    context 'with the endpoint configured for exponential backoff' do
      let(:backoff) { 'exponential' }

      it 'schedules the next retry using the configured exponential backoff' do
        report_failure!

        expect(response).to have_http_status(:ok)
        delivery.reload
        expect(delivery.status).to eq('failed')
        # attempt_number 1, exponential => 2**1 = 2 minutes from now (NOT dropped).
        expect(delivery.next_retry_at).to be_present
        expect(delivery.next_retry_at).to be_within(30.seconds).of(2.minutes.from_now)
      end
    end

    context 'with the endpoint configured for linear backoff' do
      let(:backoff) { 'linear' }

      it 'schedules the next retry using the configured linear backoff' do
        report_failure!

        expect(response).to have_http_status(:ok)
        delivery.reload
        # attempt_number 1, linear => 1 * 5 = 5 minutes from now. A different
        # value than exponential proves the configured backoff is actually read.
        expect(delivery.next_retry_at).to be_present
        expect(delivery.next_retry_at).to be_within(30.seconds).of(5.minutes.from_now)
      end
    end

    context 'when the configured retry_limit is exhausted' do
      let(:backoff) { 'exponential' }
      let(:delivery) do
        create(:webhook_delivery,
               webhook_endpoint: endpoint,
               webhook_event: webhook_event,
               status: 'pending',
               attempt_number: 3) # == retry_limit
      end

      it 'does not schedule a further retry' do
        report_failure!

        expect(response).to have_http_status(:ok)
        delivery.reload
        expect(delivery.status).to eq('failed')
        expect(delivery.next_retry_at).to be_nil
      end
    end
  end
end
