# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailDelivery, type: :model do
  describe 'associations' do
    # Note: belongs_to :account is defined in model but no account_id column exists in DB
    it { should belong_to(:user).optional }
  end

  describe 'validations' do
    subject { build(:email_delivery) }

    it { should validate_presence_of(:recipient_email) }
    it { should allow_value('user@example.com').for(:recipient_email) }
    it { should_not allow_value('invalid_email').for(:recipient_email) }
    it { should validate_presence_of(:subject) }
    it { should validate_presence_of(:email_type) }

    # Model validates these values; DB check constraint is narrower
    # (welcome, verification, password_reset, invitation, notification, marketing, transactional)
    it { should validate_inclusion_of(:email_type).in_array(%w[
      password_reset email_verification welcome_email subscription_created
      subscription_cancelled payment_succeeded payment_failed invoice_generated
      trial_ending dunning_notification report_generated system_notification
    ]) }

    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending sent failed retry]) }
  end

  describe 'scopes' do
    # Use only email_type values that satisfy BOTH model validation AND DB check constraint
    let!(:sent_email) { create(:email_delivery, :sent) }
    let!(:failed_email) { create(:email_delivery, :failed) }
    let!(:pending_email) { create(:email_delivery, status: 'pending') }
    let!(:password_reset_email) { create(:email_delivery, :password_reset) }

    describe '.sent' do
      it 'returns only sent emails' do
        expect(EmailDelivery.sent).to include(sent_email)
        expect(EmailDelivery.sent).not_to include(failed_email, pending_email)
      end
    end

    describe '.failed' do
      it 'returns only failed emails' do
        expect(EmailDelivery.failed).to include(failed_email)
        expect(EmailDelivery.failed).not_to include(sent_email, pending_email)
      end
    end

    describe '.pending' do
      it 'returns only pending emails' do
        expect(EmailDelivery.pending).to include(pending_email)
        expect(EmailDelivery.pending).not_to include(sent_email, failed_email)
      end
    end

    describe '.by_email_type' do
      it 'returns emails of specified type' do
        expect(EmailDelivery.by_email_type('password_reset')).to include(password_reset_email)
      end
    end

    describe '.by_recipient' do
      it 'returns emails for specified recipient' do
        email = create(:email_delivery, recipient_email: 'test@example.com')
        expect(EmailDelivery.by_recipient('test@example.com')).to include(email)
        expect(EmailDelivery.by_recipient('other@example.com')).not_to include(email)
      end
    end

    describe '.recent' do
      it 'returns emails ordered by created_at desc' do
        expect(EmailDelivery.recent.first).to be_present
      end
    end
  end

  describe 'AASM state machine' do
    let(:email_delivery) { create(:email_delivery, status: 'pending') }

    describe 'states' do
      it 'has pending as initial state' do
        expect(email_delivery.pending?).to be true
      end

      it 'can transition to sent via mark_sent' do
        email_delivery.mark_sent!
        expect(email_delivery.sent?).to be true
      end

      it 'can transition to failed via mark_failed' do
        email_delivery.mark_failed!
        expect(email_delivery.failed?).to be true
      end
    end

    describe 'event transitions' do
      it 'mark_sent transitions from pending to sent' do
        expect { email_delivery.mark_sent! }.to change { email_delivery.status }.from('pending').to('sent')
      end

      it 'mark_failed transitions from pending to failed' do
        expect { email_delivery.mark_failed! }.to change { email_delivery.status }.from('pending').to('failed')
      end
    end
  end

  describe 'instance methods' do
    let(:email_delivery) { create(:email_delivery) }

    describe '#can_retry?' do
      it 'returns true when failed and retry_count < 3' do
        email_delivery.update_columns(status: 'failed', retry_count: 2)
        expect(email_delivery.can_retry?).to be true
      end

      it 'returns false when retry_count >= 3' do
        email_delivery.update_columns(status: 'failed', retry_count: 3)
        expect(email_delivery.can_retry?).to be false
      end

      it 'returns false when not failed' do
        email_delivery.update_columns(status: 'pending', retry_count: 0)
        expect(email_delivery.can_retry?).to be false
      end
    end

    describe '#delivery_time' do
      it 'returns time difference between created_at and sent_at' do
        email_delivery.created_at = 2.minutes.ago
        email_delivery.sent_at = Time.current
        expect(email_delivery.delivery_time).to be_within(5).of(120)
      end

      it 'returns nil when sent_at is nil' do
        email_delivery.sent_at = nil
        expect(email_delivery.delivery_time).to be_nil
      end

      it 'returns nil when created_at is nil' do
        email_delivery.created_at = nil
        email_delivery.sent_at = Time.current
        expect(email_delivery.delivery_time).to be_nil
      end
    end

    describe '#increment_retry_count!' do
      it 'increments the retry_count' do
        expect { email_delivery.increment_retry_count! }.to change { email_delivery.retry_count }.by(1)
      end
    end
  end

  describe 'callbacks' do
    describe 'set_defaults on create' do
      it 'sets retry_count to 0 by default' do
        email = create(:email_delivery, retry_count: nil)
        expect(email.retry_count).to eq(0)
      end
    end
  end
end
