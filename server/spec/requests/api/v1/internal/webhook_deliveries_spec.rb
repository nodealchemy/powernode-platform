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

  # IMP-3e7c104f2b36 — the webhook form promises receivers a way to verify a
  # delivery, and the page shows the signing secret once on create for it, but
  # no delivery carried a signature. The server now hands the worker the exact
  # body to send plus its signature; the secret itself never leaves the server,
  # not even to the worker.
  describe 'GET /api/v1/internal/webhook_deliveries/:id (signed delivery)' do
    let(:endpoint) { create(:webhook_endpoint, account: account, payload_detail_level: detail_level) }
    let(:detail_level) { 'full' }
    let(:delivery) do
      create(:webhook_delivery, webhook_endpoint: endpoint, webhook_event: webhook_event, status: 'pending')
    end

    def fetch!
      get api_v1_internal_webhook_delivery_path(delivery), headers: internal_headers
      expect(response).to have_http_status(:ok)
      JSON.parse(response.body)['data']
    end

    it 'returns the body to send and a timestamped HMAC-SHA256 signature of it keyed by the secret_key' do
      data = fetch!

      body = data['body']
      # Content, not byte order: the payload round-trips through jsonb. The
      # signature checks below pin the exact bytes that were signed.
      expect(JSON.parse(body)).to eq(endpoint.trim_payload(webhook_event.reload.payload).as_json)

      signature = data.dig('signature_headers', 'X-Powernode-Signature')
      timestamp = data.dig('signature_headers', 'X-Powernode-Timestamp')
      expect(signature).to match(/\At=\d+,v1=\h{64}\z/)
      expect(signature).to start_with("t=#{timestamp},")
      expect(Security::WebhookAuthenticator.verify_timestamped(payload: body, header: signature,
                                                               secret: endpoint.secret_key)).to be(true)
      expected_hmac = OpenSSL::HMAC.hexdigest('SHA256', endpoint.secret_key, "#{timestamp}.#{body}")
      expect(signature).to end_with("v1=#{expected_hmac}")
    end

    it 'never puts the secret in the response' do
      fetch!

      expect(response.body).not_to include(endpoint.secret_key)
    end

    context 'with a trimmed payload detail level' do
      let(:detail_level) { 'ids_only' }

      it 'signs the trimmed body, which is the body sent' do
        data = fetch!

        expect(JSON.parse(data['body'])).to eq(endpoint.trim_payload(webhook_event.reload.payload).as_json)
        expect(Security::WebhookAuthenticator.verify_timestamped(
          payload: data['body'], header: data.dig('signature_headers', 'X-Powernode-Signature'),
          secret: endpoint.secret_key
        )).to be(true)
      end
    end
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
