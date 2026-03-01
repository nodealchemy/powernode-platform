# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notification, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:notification) }

    it { should validate_presence_of(:notification_type) }
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:message) }
    it { should validate_presence_of(:severity) }
    it { should validate_inclusion_of(:severity).in_array(%w[info success warning error]) }
  end

  describe 'scopes' do
    let!(:account) { create(:account) }
    let!(:user) { create(:user, account: account) }
    let!(:unread_notification) { create(:notification, :unread, account: account, user: user) }
    let!(:read_notification) { create(:notification, :read, account: account, user: user) }
    let!(:dismissed_notification) { create(:notification, :dismissed, account: account, user: user) }
    let!(:expired_notification) { create(:notification, :expired, account: account, user: user) }
    let!(:billing_notification) { create(:notification, :billing, account: account, user: user) }
    let!(:security_notification) { create(:notification, :security, account: account, user: user) }

    describe '.unread' do
      it 'returns only unread notifications' do
        expect(Notification.unread).to include(unread_notification)
        expect(Notification.unread).not_to include(read_notification)
      end
    end

    describe '.read' do
      it 'returns only read notifications' do
        expect(Notification.read).to include(read_notification)
        expect(Notification.read).not_to include(unread_notification)
      end
    end

    describe '.not_dismissed' do
      it 'returns only non-dismissed notifications' do
        expect(Notification.not_dismissed).to include(unread_notification, read_notification)
        expect(Notification.not_dismissed).not_to include(dismissed_notification)
      end
    end

    describe '.not_expired' do
      it 'returns only non-expired notifications' do
        expect(Notification.not_expired).to include(unread_notification, read_notification)
        expect(Notification.not_expired).not_to include(expired_notification)
      end
    end

    describe '.active' do
      it 'returns only active notifications' do
        active_notifications = Notification.active
        expect(active_notifications).to include(unread_notification, read_notification)
        expect(active_notifications).not_to include(dismissed_notification, expired_notification)
      end
    end

    describe '.recent' do
      it 'returns notifications ordered by created_at desc' do
        expect(Notification.recent.first).to be_present
      end
    end

    describe '.by_category' do
      it 'returns notifications with specified category' do
        expect(Notification.by_category('billing')).to include(billing_notification)
        expect(Notification.by_category('billing')).not_to include(security_notification)
      end
    end

    describe '.by_type' do
      it 'returns notifications with specified type' do
        expect(Notification.by_type('billing_reminder')).to include(billing_notification)
        expect(Notification.by_type('security_alert')).to include(security_notification)
      end
    end
  end

  describe 'instance methods' do
    let(:notification) { create(:notification) }

    describe '#read?' do
      it 'returns true when read_at is present' do
        notification.read_at = Time.current
        expect(notification.read?).to be true
      end

      it 'returns false when read_at is nil' do
        notification.read_at = nil
        expect(notification.read?).to be false
      end
    end

    describe '#dismissed?' do
      it 'returns true when dismissed_at is present' do
        notification.dismissed_at = Time.current
        expect(notification.dismissed?).to be true
      end

      it 'returns false when dismissed_at is nil' do
        notification.dismissed_at = nil
        expect(notification.dismissed?).to be false
      end
    end

    describe '#expired?' do
      it 'returns true when expires_at is in the past' do
        notification.expires_at = 1.day.ago
        expect(notification.expired?).to be true
      end

      it 'returns false when expires_at is in the future' do
        notification.expires_at = 1.day.from_now
        expect(notification.expired?).to be false
      end

      it 'returns false when expires_at is nil' do
        notification.expires_at = nil
        expect(notification.expired?).to be false
      end
    end

    describe '#mark_as_read!' do
      it 'sets read_at to current time' do
        notification.read_at = nil
        expect { notification.mark_as_read! }.to change { notification.reload.read_at }.from(nil).to(be_within(1.second).of(Time.current))
      end

      it 'does not update if already read' do
        notification.update!(read_at: 1.day.ago)
        original_time = notification.read_at
        notification.mark_as_read!
        expect(notification.reload.read_at).to eq(original_time)
      end
    end

    describe '#mark_as_unread!' do
      it 'sets read_at to nil' do
        notification.update!(read_at: Time.current)
        expect { notification.mark_as_unread! }.to change { notification.reload.read_at }.to(nil)
      end

      it 'does not update if already unread' do
        notification.update!(read_at: nil)
        expect(notification).not_to receive(:update!)
        notification.mark_as_unread!
      end
    end

    describe '#dismiss!' do
      it 'sets dismissed_at to current time' do
        notification.dismissed_at = nil
        expect { notification.dismiss! }.to change { notification.reload.dismissed_at }.from(nil).to(be_within(1.second).of(Time.current))
      end

      it 'does not update if already dismissed' do
        notification.update!(dismissed_at: 1.day.ago)
        original_time = notification.dismissed_at
        notification.dismiss!
        expect(notification.reload.dismissed_at).to eq(original_time)
      end
    end
  end
end
