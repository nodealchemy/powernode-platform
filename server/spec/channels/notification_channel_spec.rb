# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NotificationChannel, type: :channel do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    stub_connection current_user: user
  end

  describe 'subscription' do
    it 'streams from the account stream' do
      subscribe(account_id: account.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("account_#{account.id}")
    end
  end

  describe 'class broadcasters' do
    it 'broadcasts a new notification to the account stream the subscriber listens on' do
      expect {
        create(:notification, account: account, user: user)
      }.to have_broadcasted_to("account_#{account.id}")
        .with(hash_including(type: "new_notification"))
    end

    it 'broadcasts all-read to the account stream' do
      expect {
        described_class.broadcast_all_read(account, count: 3)
      }.to have_broadcasted_to("account_#{account.id}")
        .with(hash_including(type: "all_notifications_read", count: 3))
    end
  end
end
