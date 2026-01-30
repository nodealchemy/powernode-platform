# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookEvent, type: :model do
  describe 'associations' do
    it { should belong_to(:account).optional }
    it { should belong_to(:payment).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:provider) }
    it { should validate_inclusion_of(:provider).in_array(%w[stripe paypal]) }
    it { should validate_presence_of(:event_type) }
    it { should validate_presence_of(:external_id) }
    it { should validate_presence_of(:payload) }
    it { should validate_numericality_of(:retry_count).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(10) }

    describe 'external_id uniqueness' do
      let(:account) { create(:account) }
      let!(:existing_event) { create(:webhook_event, account: account, external_id: 'evt_unique_123') }

      it 'validates uniqueness of external_id' do
        duplicate_event = build(:webhook_event, account: account, external_id: 'evt_unique_123')
        expect(duplicate_event).not_to be_valid
        expect(duplicate_event.errors[:external_id]).to include('has already been taken')
      end

      it 'allows different external_ids' do
        new_event = build(:webhook_event, account: account, external_id: 'evt_unique_456')
        expect(new_event).to be_valid
      end
    end
  end

  describe 'AASM states' do
    let(:account) { create(:account) }
    let(:event) { create(:webhook_event, account: account) }

    it 'has pending as initial state' do
      expect(event.status).to eq('pending')
    end

    describe 'state transitions' do
      describe 'start_processing' do
        it 'transitions from pending to processing' do
          event.start_processing!
          expect(event.status).to eq('processing')
        end

        it 'transitions from failed to processing' do
          failed_event = create(:webhook_event, :failed, account: account)
          failed_event.start_processing!
          expect(failed_event.status).to eq('processing')
        end

        it 'does not transition from processed' do
          event.start_processing!
          event.mark_processed!
          expect { event.start_processing! }.to raise_error(AASM::InvalidTransition)
        end
      end

      describe 'mark_processed' do
        it 'transitions from processing to processed' do
          event.start_processing!
          event.mark_processed!
          expect(event.status).to eq('processed')
        end

        it 'does not transition from pending' do
          expect { event.mark_processed! }.to raise_error(AASM::InvalidTransition)
        end
      end

      describe 'mark_failed' do
        it 'transitions from processing to failed' do
          event.start_processing!
          event.mark_failed!
          expect(event.status).to eq('failed')
        end

        it 'increments retry_count on failure' do
          event.start_processing!
          expect { event.mark_failed! }.to change { event.reload.retry_count }.by(1)
        end

        it 'does not transition from pending' do
          expect { event.mark_failed! }.to raise_error(AASM::InvalidTransition)
        end
      end

      describe 'skip' do
        it 'transitions from pending to skipped' do
          event.skip!
          expect(event.status).to eq('skipped')
        end

        it 'transitions from failed to skipped' do
          failed_event = create(:webhook_event, :failed, account: account)
          failed_event.skip!
          expect(failed_event.status).to eq('skipped')
        end

        it 'does not transition from processing' do
          event.start_processing!
          expect { event.skip! }.to raise_error(AASM::InvalidTransition)
        end
      end
    end
  end

  describe 'instance methods' do
    let(:account) { create(:account) }

    describe '#can_retry?' do
      it 'returns true when failed and retry_count is less than 10' do
        event = create(:webhook_event, :failed, account: account, retry_count: 5)
        expect(event.can_retry?).to be true
      end

      it 'returns false when retry_count is 10' do
        event = create(:webhook_event, :failed, account: account, retry_count: 10)
        expect(event.can_retry?).to be false
      end

      it 'returns false when not in failed state' do
        event = create(:webhook_event, account: account)
        expect(event.can_retry?).to be false
      end
    end

    describe '#should_retry?' do
      it 'returns true when failed and can retry without permanent failure' do
        event = create(:webhook_event, :failed, account: account, retry_count: 3, error_message: 'Connection timeout')
        expect(event.should_retry?).to be true
      end

      it 'returns false when not in failed state' do
        event = create(:webhook_event, account: account)
        expect(event.should_retry?).to be false
      end

      it 'returns false when retry_count is at maximum' do
        event = create(:webhook_event, :failed, account: account, retry_count: 10)
        expect(event.should_retry?).to be false
      end

      it 'returns false when error is a permanent failure' do
        event = create(:webhook_event, :failed, account: account, retry_count: 1, error_message: 'Signature verification failed')
        expect(event.should_retry?).to be false
      end
    end

    describe '#next_retry_at' do
      it 'returns nil when should_retry? is false' do
        event = create(:webhook_event, account: account)
        expect(event.next_retry_at).to be_nil
      end

      it 'returns a future time when should_retry? is true' do
        event = create(:webhook_event, :failed, account: account, retry_count: 1, error_message: 'Connection timeout')
        expect(event.next_retry_at).to be > Time.current
      end
    end

    describe '#event_data_parsed' do
      it 'parses JSON payload' do
        event = create(:webhook_event, account: account, payload: '{"key": "value"}')
        expect(event.event_data_parsed).to eq({ 'key' => 'value' })
      end

      it 'returns empty hash for invalid JSON' do
        event = create(:webhook_event, account: account, payload: 'invalid json')
        expect(event.event_data_parsed).to eq({})
      end
    end

    describe '#stripe?' do
      it 'returns true when provider is stripe' do
        event = build(:webhook_event, provider: 'stripe')
        expect(event.stripe?).to be true
      end

      it 'returns false when provider is not stripe' do
        event = build(:webhook_event, provider: 'paypal')
        expect(event.stripe?).to be false
      end
    end

    describe '#paypal?' do
      it 'returns true when provider is paypal' do
        event = build(:webhook_event, provider: 'paypal')
        expect(event.paypal?).to be true
      end

      it 'returns false when provider is not paypal' do
        event = build(:webhook_event, provider: 'stripe')
        expect(event.paypal?).to be false
      end
    end

    describe '#add_error' do
      it 'updates the error_message' do
        event = create(:webhook_event, account: account)
        event.add_error('Something went wrong')
        expect(event.reload.error_message).to eq('Something went wrong')
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let!(:pending_event) { create(:webhook_event, :pending, account: account) }
    let!(:processed_event) { create(:webhook_event, :processed, account: account) }
    let!(:failed_event) { create(:webhook_event, :failed, account: account) }

    describe '.pending' do
      it 'returns only pending events' do
        expect(described_class.pending).to include(pending_event)
        expect(described_class.pending).not_to include(processed_event, failed_event)
      end
    end

    describe '.processed' do
      it 'returns only processed events' do
        expect(described_class.processed).to include(processed_event)
        expect(described_class.processed).not_to include(pending_event, failed_event)
      end
    end

    describe '.failed' do
      it 'returns only failed events' do
        expect(described_class.failed).to include(failed_event)
        expect(described_class.failed).not_to include(pending_event, processed_event)
      end
    end

    describe '.for_provider' do
      let!(:stripe_event) { create(:webhook_event, :stripe, account: account) }
      let!(:paypal_event) { create(:webhook_event, :paypal, account: account) }

      it 'returns events for the specified provider' do
        expect(described_class.for_provider('stripe')).to include(stripe_event)
        expect(described_class.for_provider('stripe')).not_to include(paypal_event)
      end
    end

    describe '.recent' do
      it 'returns events ordered by created_at descending' do
        results = described_class.recent
        expect(results.first.created_at).to be >= results.last.created_at
      end
    end
  end
end
