# frozen_string_literal: true

class NotificationChannel < ApplicationCable::Channel
  def subscribed
    account_id = params[:account_id]

    if current_user && authorized_for_account?(account_id)
      stream_for_account(current_account)

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

  # Class method to broadcast notifications to account
  class << self
    def broadcast_to_account(account, data)
      broadcast_to(account, data)
    end

    def broadcast_new_notification(notification)
      broadcast_to_account(notification.account, {
        type: 'new_notification',
        notification: notification.as_json(
          only: [:id, :notification_type, :title, :message, :severity, :action_url, :action_label, :icon, :category, :created_at]
        )
      })
    end

    def broadcast_notification_read(notification)
      broadcast_to_account(notification.account, {
        type: 'notification_read',
        notification_id: notification.id
      })
    end
  end
end
