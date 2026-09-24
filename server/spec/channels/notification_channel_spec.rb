# frozen_string_literal: true

require 'rails_helper'

# IMP-01a04dac-1083. Every event this channel carries belongs to ONE user — a
# Notification belongs_to :user and every REST read is current_user.notifications;
# the settings sync ships current_user's own preferences to "all user's
# sessions" — but every broadcaster published to the ACCOUNT stream, which
# every user of the account subscribes to. So:
#
#   - a coworker's bell received a user's notification title, message,
#     action_url and metadata the REST API would never show them;
#   - one user's "mark all read" / "dismiss all" reached every coworker's
#     client, whose onAllRead / onAllDismissed handlers mark every LOCAL row
#     read or clear the list outright — wiping someone else's bell;
#   - one user's preferences save reached every coworker's ProfilePage, which
#     merges the payload into its own form state and calls setTheme — changing
#     another person's theme and preloading their form with foreign settings.
#
# The previous version of this file asserted the account stream as the intended
# destination, which is how the defect stayed pinned in place.
#
# The per-user stream is NAMESPACED ("notifications:user:<id>"), following the
# mission / code_factory convention: ActionCable stream names are global, so a
# bare "user_<id>" would receive anything any other channel ever publishes
# under that name — the cross-delivery this change exists to remove.
#
# Every isolation example (`not_to have_broadcasted_to`) sits beside a POSITIVE
# delivery example on the owner's stream: a negative matcher alone passes on
# any mistyped stream name and proves nothing.
RSpec.describe NotificationChannel, type: :channel do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:coworker) { create(:user, account: account) }

  def user_stream(u) = "notifications:user:#{u.id}"
  let(:account_stream) { "account_#{account.id}" }

  before do
    stub_connection current_user: user
  end

  describe 'subscription' do
    it 'streams from the subscriber\'s own namespaced user stream' do
      subscribe(account_id: account.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from(user_stream(user))
    end

    # Nothing account-wide rides this channel any more, so an account
    # subscription would only ever deliver other people's events.
    it 'no longer streams from the account stream' do
      subscribe(account_id: account.id)

      expect(subscription).not_to have_stream_from(account_stream)
    end

    it 'still refuses a subscription for another account' do
      subscribe(account_id: create(:account).id)

      expect(subscription).to be_rejected
    end
  end

  # N2: a socket opened BEFORE maintenance mode was enabled is otherwise
  # never re-checked once its initial handshake passes — these chokepoints
  # (before_subscribe + ApplicationCable::Channel#perform_action) exist so
  # every channel that inherits from it stops being usable once maintenance
  # turns on mid-session, with no per-channel code required.
  describe 'maintenance mode (ApplicationCable::Channel base-class gate)' do
    # `verify_partial_doubles` (spec_helper.rb) refuses to stub a method a
    # double doesn't already define — ConnectionStub has no #close (only
    # #transmit), so it's defined here first, making
    # `connection.respond_to?(:close)` true and the subsequent `close`
    # branch (not the reject-fallback) run for real.
    def stub_connection_close(conn)
      conn.define_singleton_method(:close) { |**_kwargs| }
    end

    after do
      Admin::MaintenanceMode.disable!
      Admin::MaintenanceMode.invalidate_cache!
    end

    it 'rejects a NEW subscription attempt while maintenance is on' do
      Admin::MaintenanceMode.enable!(message: 'Upgrading')
      Admin::MaintenanceMode.invalidate_cache!

      subscribe(account_id: account.id)

      expect(subscription).to be_rejected
    end

    it 'closes with the distinct maintenance_mode reason when an already-subscribed (grandfathered) connection performs an action' do
      stub_connection_close(connection)
      subscribe(account_id: account.id)
      expect(subscription).to be_confirmed

      Admin::MaintenanceMode.enable!(message: 'Upgrading')
      Admin::MaintenanceMode.invalidate_cache!

      expect(connection).to receive(:close).with(reason: 'maintenance_mode', reconnect: false)
      perform :ping
    end

    it 'closes a PASSIVE subscriber (never calls an action) via the periodic re-check' do
      stub_connection_close(connection)
      subscribe(account_id: account.id)
      expect(subscription).to be_confirmed

      Admin::MaintenanceMode.enable!(message: 'Upgrading')
      Admin::MaintenanceMode.invalidate_cache!

      # periodically's real timer never fires in this harness (ChannelStub
      # makes start_periodic_timers a no-op) — invoke the registered
      # callback directly, same technique as testing any other private hook.
      expect(connection).to receive(:close).with(reason: 'maintenance_mode', reconnect: false)
      subscription.send(:enforce_maintenance!)
    end

    it 'exempts a system.admin holder from the subscribe-time, perform-time, AND periodic checks' do
      admin = create(:user, account: account, permissions: [ 'system.admin' ])
      stub_connection current_user: admin
      stub_connection_close(connection)
      Admin::MaintenanceMode.enable!(message: 'Upgrading')
      Admin::MaintenanceMode.invalidate_cache!

      subscribe(account_id: account.id)
      expect(subscription).to be_confirmed

      expect(connection).not_to receive(:close)
      perform :ping
      subscription.send(:enforce_maintenance!)
      expect(subscription).not_to be_rejected
    end

    # Item 1 (HIGH fix): `request` is private on ActionCable::Connection::Base,
    # so a Channel reads the remote IP via the new public
    # Connection#maintenance_remote_ip instead — this is what actually lets a
    # bypass-listed non-admin through the Channel-level gate.
    it 'exempts a non-admin connecting from a configured bypass IP' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        Admin::MaintenanceMode.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])
        Admin::MaintenanceMode.invalidate_cache!

        stub_connection_close(connection)
        connection.define_singleton_method(:maintenance_remote_ip) { '203.0.113.5' }

        subscribe(account_id: account.id)
        expect(subscription).to be_confirmed

        expect(connection).not_to receive(:close)
        perform :ping
      end
    end
  end

  describe 'a new notification' do
    it 'is delivered to its owner' do
      expect {
        create(:notification, account: account, user: user)
      }.to have_broadcasted_to(user_stream(user))
        .with(hash_including(type: "new_notification"))
    end

    it 'is NOT delivered to the account stream or to a same-account coworker' do
      expect {
        create(:notification, account: account, user: user)
      }.not_to have_broadcasted_to(account_stream)

      expect {
        create(:notification, account: account, user: user)
      }.not_to have_broadcasted_to(user_stream(coworker))
    end
  end

  describe 'read and dismiss events' do
    let(:notification) { create(:notification, account: account, user: user) }

    before { notification } # created outside the expectation blocks below

    it 'sends a single read only to the owner' do
      expect {
        described_class.broadcast_notification_read(notification)
      }.to have_broadcasted_to(user_stream(user))
        .with(hash_including(type: "notification_read", notification_id: notification.id))
    end

    it 'sends a single dismiss only to the owner' do
      expect {
        described_class.broadcast_notification_dismissed(notification)
      }.to have_broadcasted_to(user_stream(user))
        .with(hash_including(type: "notification_dismissed", notification_id: notification.id))
    end

    # The events that WIPED a coworker's bell: their handlers mark every local
    # row read, or clear the list, with no id to scope by.
    it 'sends all-read only to the user who marked them' do
      expect {
        described_class.broadcast_all_read(user, count: 3)
      }.to have_broadcasted_to(user_stream(user))
        .with(hash_including(type: "all_notifications_read", count: 3))
    end

    it 'sends all-dismissed only to the user who dismissed them' do
      expect {
        described_class.broadcast_all_dismissed(user, count: 2)
      }.to have_broadcasted_to(user_stream(user))
        .with(hash_including(type: "all_notifications_dismissed", count: 2))
    end

    it 'keeps every read/dismiss event off the account stream and off a coworker' do
      expect {
        described_class.broadcast_notification_read(notification)
        described_class.broadcast_notification_dismissed(notification)
        described_class.broadcast_all_read(user, count: 3)
        described_class.broadcast_all_dismissed(user, count: 2)
      }.not_to have_broadcasted_to(account_stream)

      expect {
        described_class.broadcast_all_read(user, count: 3)
      }.not_to have_broadcasted_to(user_stream(coworker))
    end
  end

  describe 'the settings sync' do
    it 'reaches the user\'s own sessions' do
      expect {
        described_class.broadcast_to_user(user, { type: "preferences_updated", data: { theme: "dark" } })
      }.to have_broadcasted_to(user_stream(user))
        .with(hash_including(type: "preferences_updated"))
    end

    it 'does not reach the account stream or a coworker' do
      expect {
        described_class.broadcast_to_user(user, { type: "preferences_updated", data: { theme: "dark" } })
      }.not_to have_broadcasted_to(account_stream)

      expect {
        described_class.broadcast_to_user(user, { type: "preferences_updated", data: { theme: "dark" } })
      }.not_to have_broadcasted_to(user_stream(coworker))
    end
  end
end
