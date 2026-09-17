# frozen_string_literal: true

require 'rails_helper'

# IMP-dd0305de2799. Before this producer existed, nothing created a
# WebhookDelivery for a platform event — a configured WebhookEndpoint
# received only manual test pings. These specs cover WHO gets a delivery and
# what STATE it lands in; the worker-enqueue behavior itself (D1: deferred to
# after_commit, so the worker is never told about a delivery before it is
# durably committed) is WebhookDelivery's own responsibility — see
# spec/models/webhook_delivery_spec.rb's "enqueue_worker_job (after_commit)"
# examples, and spec/integration/webhook_platform_event_delivery_spec.rb for
# the full real-event, real-commit, real-signature path.
RSpec.describe WebhookEventPublisher do
  let(:account) { create(:account) }

  describe '.publish' do
    it 'creates a WebhookDelivery (pending) and a system-provider WebhookEvent for a subscribed active endpoint' do
      endpoint = create(:webhook_endpoint, account: account, status: 'active', event_types: [ 'user.created' ])

      expect {
        described_class.publish(event_type: 'user.created', account: account, payload: { 'id' => 'u1' })
      }.to change(WebhookDelivery, :count).by(1)
        .and change(WebhookEvent, :count).by(1)

      delivery = WebhookDelivery.last
      expect(delivery.webhook_endpoint).to eq(endpoint)
      expect(delivery.status).to eq('pending')
      expect(delivery.webhook_event.provider).to eq('system')
      expect(delivery.webhook_event.event_type).to eq('user.created')
    end

    it 'does not create a delivery for an endpoint not subscribed to the event_type' do
      create(:webhook_endpoint, account: account, status: 'active', event_types: [ 'account.created' ])

      expect {
        described_class.publish(event_type: 'user.created', account: account, payload: {})
      }.not_to change(WebhookDelivery, :count)
    end

    it 'does not create a delivery for an inactive endpoint' do
      create(:webhook_endpoint, account: account, status: 'inactive', event_types: [ 'user.created' ])

      expect {
        described_class.publish(event_type: 'user.created', account: account, payload: {})
      }.not_to change(WebhookDelivery, :count)
    end

    it 'does not create a delivery for a circuit-broken endpoint (can_receive_event? is false)' do
      create(:webhook_endpoint, account: account, status: 'active', event_types: [ 'user.created' ],
                                 circuit_broken_at: Time.current, circuit_cooldown_until: 1.hour.from_now)

      expect {
        described_class.publish(event_type: 'user.created', account: account, payload: {})
      }.not_to change(WebhookDelivery, :count)
    end

    it 'fans out to every matching active endpoint on the account' do
      e1 = create(:webhook_endpoint, account: account, status: 'active', event_types: [ 'user.created' ])
      e2 = create(:webhook_endpoint, account: account, status: 'active', event_types: [ '*' ])

      expect {
        described_class.publish(event_type: 'user.created', account: account, payload: { 'id' => 'evt-1' })
      }.to change(WebhookDelivery, :count).by(2)

      expect(WebhookDelivery.pluck(:webhook_endpoint_id)).to contain_exactly(e1.id, e2.id)
    end

    it 'is a no-op when the account is nil' do
      expect {
        described_class.publish(event_type: 'user.created', account: nil, payload: {})
      }.not_to change(WebhookDelivery, :count)
    end

    it 'is a no-op when no endpoint on the account matches' do
      other_account = create(:account)
      create(:webhook_endpoint, account: other_account, status: 'active', event_types: [ 'user.created' ])

      expect {
        described_class.publish(event_type: 'user.created', account: account, payload: {})
      }.not_to change(WebhookDelivery, :count)
    end

    context 'when the matching endpoint is over its tier daily limit' do
      it 'records a failed delivery that was never attempted (D2): attempted_at nil, no endpoint-stat increment' do
        endpoint = create(:webhook_endpoint, account: account, status: 'active',
                                              event_types: [ 'user.created' ], tier: 'free',
                                              daily_count: 100, daily_limit: 100,
                                              # Strictly AFTER beginning_of_day, or
                                              # reset_daily_count_if_needed! (called by the
                                              # publisher before the rate-limit check) treats
                                              # this as a stale counter and zeroes it, hiding
                                              # the very state this test sets up.
                                              daily_count_reset_at: Time.current)

        expect {
          described_class.publish(event_type: 'user.created', account: account, payload: { 'id' => 'evt-1' })
        }.to change(WebhookDelivery, :count).by(1)

        delivery = WebhookDelivery.last
        expect(delivery.webhook_endpoint).to eq(endpoint)
        expect(delivery.status).to eq('failed')
        expect(delivery.error_message).to match(/daily delivery limit/i)
        expect(delivery.attempted_at).to be_nil
        # D2's actual claim: this "failed" status must NOT be counted as a
        # real endpoint failure (it was never attempted).
        expect(endpoint.reload.failure_count).to eq(0)
      end

      it 'still shows up in delivery_history (visible, not hidden)' do
        endpoint = create(:webhook_endpoint, account: account, status: 'active',
                                              event_types: [ 'user.created' ], tier: 'free',
                                              daily_count: 100, daily_limit: 100,
                                              daily_count_reset_at: Time.current)

        described_class.publish(event_type: 'user.created', account: account, payload: { 'id' => 'evt-1' })

        expect(endpoint.webhook_deliveries.count).to eq(1)
      end
    end
  end

  describe '.event_type_for' do
    it 'maps a generic Auditable create/update/delete action to the matching platform event_type' do
      user = build_stubbed(:user)

      expect(described_class.event_type_for(user, 'created')).to eq('user.created')
      expect(described_class.event_type_for(user, 'updated')).to eq('user.updated')
      expect(described_class.event_type_for(user, 'deleted')).to eq('user.deleted')
    end

    it 'returns nil for an action with no corresponding entry in WebhookEndpoint.available_event_types' do
      validation_rule = build_stubbed(:validation_rule)

      expect(described_class.event_type_for(validation_rule, 'created')).to be_nil
    end

    it 'returns nil for a non create/update/delete action' do
      user = build_stubbed(:user)

      expect(described_class.event_type_for(user, 'account_created')).to be_nil
    end

    # Discriminates the action-name guard from the enum-membership check below
    # it: "account.suspended" IS a real WebhookEndpoint.available_event_types
    # entry, so a version of event_type_for that dropped the create/update/delete
    # allowlist (and relied on the enum check alone) would still wrongly map
    # this — the enum check alone cannot catch that regression.
    it 'returns nil even when the derived domain.action string is itself a real enum entry' do
      account = build_stubbed(:account)

      expect(described_class.event_type_for(account, 'suspended')).to be_nil
    end
  end
end
