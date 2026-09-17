# frozen_string_literal: true

require 'rails_helper'

# IMP-dd0305de2799, end to end. Before WebhookEventPublisher existed, nothing
# in server/app, extensions/*/server/app or worker/app ever created a
# WebhookDelivery row or enqueued Webhooks::WebhookDeliveryJob for a real
# platform event — a configured WebhookEndpoint received only manual test
# pings (POST /api/v1/webhooks/:id/test), never the event traffic its
# event_types promised. This fires a REAL event (creating a User, under the
# same Auditable machinery every controller already goes through — no test
# double stands in for the producer path) and asserts the acceptance
# criterion: the WebhookDelivery row, the enqueue of Webhooks::WebhookDeliveryJob
# through the worker HTTP-dispatch seam (after commit — D1), and the signed
# X-Powernode-Signature / X-Powernode-Timestamp headers, driven through the
# REAL internal controller rather than re-verified with the signing module
# under test (D7).
RSpec.describe 'Webhook platform event delivery (end to end)', type: :request do
  let(:account) { create(:account) }
  let(:worker_api_client) { instance_double(WorkerApiClient, queue_job: { 'success' => true }) }

  # Worker mTLS auth for the internal delivery-fetch endpoint (Api::V1::Internal::WebhookDeliveriesController),
  # same convention as spec/requests/api/v1/internal/webhook_deliveries_spec.rb.
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  before { allow(WorkerApiClient).to receive(:new).and_return(worker_api_client) }

  around { |example| Auditable.with_logging { example.run } }

  it 'creates a WebhookDelivery and enqueues Webhooks::WebhookDeliveryJob after commit when a User is created' do
    endpoint = create(:webhook_endpoint, account: account, status: 'active', event_types: [ 'user.created' ])

    user = nil
    expect {
      user = create(:user, account: account)
    }.to change(WebhookDelivery, :count).by(1)

    delivery = WebhookDelivery.last
    expect(delivery.webhook_endpoint).to eq(endpoint)
    expect(delivery.status).to eq('pending')

    webhook_event = delivery.webhook_event
    expect(webhook_event.event_type).to eq('user.created')
    expect(webhook_event.provider).to eq('system')
    expect(webhook_event.payload['id']).to eq(user.id)
    expect(webhook_event.payload['account_id']).to eq(account.id)

    expect(worker_api_client).to have_received(:queue_job)
      .with('Webhooks::WebhookDeliveryJob', [ delivery.id ], queue: 'webhooks')
  end

  it 'does not create a delivery when no endpoint subscribes to user.created' do
    create(:webhook_endpoint, account: account, status: 'active', event_types: [ 'account.updated' ])

    expect { create(:user, account: account) }.not_to change(WebhookDelivery, :count)
    expect(worker_api_client).not_to have_received(:queue_job)
  end

  # D7: drives the REAL Api::V1::Internal::WebhookDeliveriesController#show
  # (the worker's actual next step, via Webhooks::WebhookDeliveryJob) rather
  # than recomputing a signature with Security::WebhookAuthenticator and then
  # re-verifying it with the same module — that would only prove the module
  # agrees with itself. X-Powernode-Signature / X-Powernode-Timestamp are the
  # operator's one explicitly named acceptance criterion.
  it 'produces a delivery the REAL internal controller signs, carrying X-Powernode-Signature / X-Powernode-Timestamp' do
    create(:webhook_endpoint, account: account, status: 'active', event_types: [ 'user.created' ])
    create(:user, account: account)
    delivery = WebhookDelivery.last

    get api_v1_internal_webhook_delivery_path(delivery), headers: internal_headers
    expect(response).to have_http_status(:ok)

    data = JSON.parse(response.body)['data']
    body = data['body']
    signature = data.dig('signature_headers', 'X-Powernode-Signature')
    timestamp = data.dig('signature_headers', 'X-Powernode-Timestamp')

    expect(JSON.parse(body)['event_type']).to eq('user.created')
    expect(signature).to match(/\At=\d+,v1=[0-9a-f]{64}\z/)
    expect(signature).to start_with("t=#{timestamp},")
    expect(Security::WebhookAuthenticator.verify_timestamped(
      payload: body, header: signature, secret: delivery.webhook_endpoint.secret_key
    )).to be(true)
  end

  # D6: the ORIGINAL example never constructed a double-fire condition (its
  # body was just `account.update!`, which a log_action-hooked build would
  # have passed unchanged). This one actually does: a second, explicit
  # AuditLog.log_action call using the SAME generic "updated" action name —
  # the shape that WOULD double-fire if this concern hooked AuditLog.log_action
  # instead of Auditable#write_audit_log, because "updated" passes the
  # event_type_for allowlist. It does not double-fire, because that raw call
  # never reaches write_audit_log in the first place.
  it 'does not double-fire when AuditLog.log_action is invoked directly with the SAME generic action for the same resource' do
    endpoint = create(:webhook_endpoint, account: account, status: 'active', event_types: [ 'account.updated' ])

    expect {
      account.update!(name: "#{account.name}-renamed")
    }.to change(WebhookDelivery, :count).by(1)
    expect(WebhookDelivery.last.webhook_endpoint).to eq(endpoint)

    expect {
      AuditLog.log_action(action: 'updated', resource: account, account: account, source: 'system')
    }.not_to change(WebhookDelivery, :count)
  end
end
