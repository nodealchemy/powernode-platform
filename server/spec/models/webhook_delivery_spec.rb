# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookDelivery, type: :model do
  describe 'associations' do
    it { should belong_to(:webhook_endpoint) }
    it { should belong_to(:webhook_event) }
  end

  describe 'validations' do
    it 'validates status inclusion' do
      delivery = described_class.new(status: 'invalid')
      delivery.valid?
      expect(delivery.errors[:status]).to be_present
    end

    it 'accepts valid status values' do
      %w[pending success failed timeout].each do |s|
        delivery = described_class.new(status: s)
        delivery.valid?
        expect(delivery.errors[:status]).to be_empty, "Expected '#{s}' to be valid"
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:endpoint) { create(:webhook_endpoint, account: account) }
    let(:event1) { create(:webhook_event, account: account) }
    let(:event2) { create(:webhook_event, account: account) }

    describe '.pending' do
      it 'returns only pending deliveries' do
        pending_d = WebhookDelivery.create!(
          webhook_endpoint: endpoint, webhook_event: event1,
          status: 'pending', attempt_number: 1
        )
        failed_d = WebhookDelivery.create!(
          webhook_endpoint: endpoint, webhook_event: event2,
          status: 'failed', attempt_number: 1
        )

        expect(described_class.pending).to include(pending_d)
        expect(described_class.pending).not_to include(failed_d)
      end
    end

    describe '.failed' do
      it 'returns only failed deliveries' do
        failed_d = WebhookDelivery.create!(
          webhook_endpoint: endpoint, webhook_event: event1,
          status: 'failed', attempt_number: 1
        )
        pending_d = WebhookDelivery.create!(
          webhook_endpoint: endpoint, webhook_event: event2,
          status: 'pending', attempt_number: 1
        )

        expect(described_class.failed).to include(failed_d)
        expect(described_class.failed).not_to include(pending_d)
      end
    end

    describe '.recent' do
      it 'returns deliveries ordered by created_at descending' do
        old_d = WebhookDelivery.create!(
          webhook_endpoint: endpoint, webhook_event: event1,
          status: 'pending', attempt_number: 1, created_at: 2.days.ago
        )
        new_d = WebhookDelivery.create!(
          webhook_endpoint: endpoint, webhook_event: event2,
          status: 'pending', attempt_number: 1, created_at: 1.hour.ago
        )

        results = described_class.recent
        expect(results.index(new_d)).to be < results.index(old_d)
      end
    end
  end

  describe 'instance methods' do
    let(:delivery) { described_class.new(status: 'pending') }

    describe '#successful?' do
      it 'returns true when status is success' do
        delivery.status = 'success'
        expect(delivery.successful?).to be true
      end

      it 'returns false when status is not success' do
        delivery.status = 'pending'
        expect(delivery.successful?).to be false
      end
    end

    describe '#failed?' do
      it 'returns true when status is failed' do
        delivery.status = 'failed'
        expect(delivery.failed?).to be true
      end

      it 'returns false when status is not failed' do
        delivery.status = 'pending'
        expect(delivery.failed?).to be false
      end
    end

    describe '#pending?' do
      it 'returns true when status is pending' do
        delivery.status = 'pending'
        expect(delivery.pending?).to be true
      end

      it 'returns false when status is not pending' do
        delivery.status = 'failed'
        expect(delivery.pending?).to be false
      end
    end

    describe '#timed_out?' do
      it 'returns true when status is timeout' do
        delivery.status = 'timeout'
        expect(delivery.timed_out?).to be true
      end

      it 'returns false when status is not timeout' do
        delivery.status = 'pending'
        expect(delivery.timed_out?).to be false
      end
    end

    describe '#duration_seconds' do
      it 'returns nil when attempted_at is nil' do
        delivery = described_class.new(created_at: Time.current, attempted_at: nil)
        expect(delivery.duration_seconds).to be_nil
      end

      it 'calculates duration between created_at and attempted_at' do
        now = Time.current
        delivery = described_class.new(created_at: now, attempted_at: now + 5.seconds)
        expect(delivery.duration_seconds).to be_within(0.1).of(5.0)
      end
    end
  end

  describe 'callbacks' do
    describe 'set_defaults' do
      it 'sets default status to pending' do
        delivery = described_class.new
        delivery.valid?
        expect(delivery.status).to eq('pending')
      end

      it 'sets default attempt_number to 1' do
        delivery = described_class.new
        delivery.valid?
        expect(delivery.attempt_number).to eq(1)
      end
    end

    # IMP-dd0305de2799, D1: the worker must never be told about a delivery
    # before it is durably committed (or after its transaction rolled back).
    describe 'enqueue_worker_job (after_commit)' do
      let(:account) { create(:account) }
      let(:endpoint) { create(:webhook_endpoint, account: account) }
      let(:event) { create(:webhook_event, account: account) }
      let(:worker_api_client) { instance_double(WorkerApiClient, queue_job: { 'success' => true }) }

      before { allow(WorkerApiClient).to receive(:new).and_return(worker_api_client) }

      it 'enqueues Webhooks::WebhookDeliveryJob only AFTER the creating transaction commits' do
        delivery = described_class.create!(webhook_endpoint: endpoint, webhook_event: event, status: 'pending')

        expect(worker_api_client).to have_received(:queue_job)
          .with('Webhooks::WebhookDeliveryJob', [ delivery.id ], queue: 'webhooks')
      end

      it 'does NOT enqueue when the creating transaction rolls back' do
        expect {
          ActiveRecord::Base.transaction do
            described_class.create!(webhook_endpoint: endpoint, webhook_event: event, status: 'pending')
            raise ActiveRecord::Rollback
          end
        }.not_to change(described_class, :count)

        expect(worker_api_client).not_to have_received(:queue_job)
      end

      it 'does NOT enqueue a delivery created with a non-pending status (e.g. the rate-limited path)' do
        described_class.create!(webhook_endpoint: endpoint, webhook_event: event, status: 'failed',
                                 error_message: 'Endpoint daily delivery limit reached')

        expect(worker_api_client).not_to have_received(:queue_job)
      end

      it 'logs and does not raise when the worker enqueue itself fails, leaving the row intact' do
        allow(worker_api_client).to receive(:queue_job).and_raise(WorkerApiClient::ApiError, 'worker down')
        allow(Rails.logger).to receive(:error)

        delivery = nil
        expect { delivery = described_class.create!(webhook_endpoint: endpoint, webhook_event: event, status: 'pending') }
          .not_to raise_error

        expect(described_class.find(delivery.id).status).to eq('pending')
        expect(Rails.logger).to have_received(:error).with(a_string_matching(/Failed to enqueue delivery #{delivery.id}/))
      end
    end

    # IMP-dd0305de2799, D2: a rate-limited delivery was never attempted and
    # must not be counted as an endpoint FAILURE.
    describe 'update_webhook_endpoint_stats with skip_endpoint_stats' do
      let(:account) { create(:account) }
      let(:endpoint) { create(:webhook_endpoint, account: account) }
      let(:event) { create(:webhook_event, account: account) }
      let(:delivery) { described_class.create!(webhook_endpoint: endpoint, webhook_event: event, status: 'pending') }

      it 'does not increment failure_count when skip_endpoint_stats is set' do
        delivery.skip_endpoint_stats = true

        expect { delivery.update!(status: 'failed', error_message: 'rate limited') }
          .not_to change { endpoint.reload.failure_count }
      end

      it 'still increments failure_count normally when skip_endpoint_stats is NOT set (a real attempt failed)' do
        expect { delivery.update!(status: 'failed', attempted_at: Time.current, error_message: 'boom') }
          .to change { endpoint.reload.failure_count }.by(1)
      end
    end
  end
end
