# frozen_string_literal: true

# Real-time delivery for ONE user's notifications and settings.
#
# Every event here belongs to a single user: a Notification belongs_to :user
# and every REST read is current_user.notifications, and the settings sync
# ships the saving user's own preferences to their own other sessions. So the
# channel streams from a PER-USER stream and nothing else (IMP-01a04dac-1083).
# It used to stream from the ACCOUNT stream, which every user of the account
# subscribes to, so a coworker's bell received other people's notification
# content, one user's "mark all read" / "dismiss all" cleared everyone's bell,
# and one user's preference save rewrote coworkers' ProfilePage state and theme.
#
# The stream name is NAMESPACED ("notifications:user:<id>"), following
# MissionChannel / CodeFactoryChannel. ActionCable stream names are global, so a
# bare "user_<id>" would deliver anything any other channel publishes under that
# name — the cross-delivery this channel exists to avoid.
class NotificationChannel < ApplicationCable::Channel
  def subscribed
    account_id = params[:account_id]

    if current_user && authorized_for_account?(account_id)
      stream_from(self.class.user_stream(current_user))

      Rails.logger.info "User #{current_user.id} subscribed to notifications for account #{account_id}"

      # Send welcome message
      transmit({
        type: "connection_established",
        message: "Connected to real-time notifications",
        timestamp: Time.current.iso8601
      })
    else
      Rails.logger.warn "Unauthorized notification subscription attempt for account #{account_id} by user #{current_user&.id}"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user&.id} unsubscribed from notifications"
  end

  # Client can send a ping to test connection
  def ping(data = {})
    # Simple pong response - client will calculate latency locally
    transmit({
      type: "pong",
      server_timestamp: Time.current.iso8601
    })
  end

  class << self
    def user_stream(user)
      "notifications:user:#{user.id}"
    end

    # The one publishing primitive. Every broadcaster below names the user the
    # event belongs to; there is deliberately no account-wide variant.
    def broadcast_to_user(user, data)
      ActionCable.server.broadcast(user_stream(user), data)
    end

    def broadcast_new_notification(notification)
      broadcast_to_user(notification.user, {
        type: "new_notification",
        notification: notification.as_json(
          only: [ :id, :notification_type, :title, :message, :severity, :action_url, :action_label, :icon, :category, :metadata, :created_at ],
          methods: [ :read? ]
        )
      })
    end

    def broadcast_notification_read(notification)
      broadcast_to_user(notification.user, {
        type: "notification_read",
        notification_id: notification.id
      })
    end

    def broadcast_notification_dismissed(notification)
      broadcast_to_user(notification.user, {
        type: "notification_dismissed",
        notification_id: notification.id
      })
    end

    # `user` is the one whose notifications were bulk-updated. The client's
    # handler marks every LOCAL row read, so this must never reach anyone else.
    def broadcast_all_read(user, count:)
      broadcast_to_user(user, {
        type: "all_notifications_read",
        count: count
      })
    end

    # As above; the client's handler clears the list outright.
    def broadcast_all_dismissed(user, count:)
      broadcast_to_user(user, {
        type: "all_notifications_dismissed",
        count: count
      })
    end
  end
end
