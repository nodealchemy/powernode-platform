# frozen_string_literal: true

# Internal API controller for worker service to send notifications
class Api::V1::Internal::NotificationsController < Api::V1::Internal::InternalBaseController
  # POST /api/v1/internal/notifications
  def create
    notification = Notification.new(notification_params)

    if notification.save
      render_success(data: notification_data(notification), status: :created)
    else
      render_validation_error(notification)
    end
  end

  # POST /api/v1/internal/notifications/send
  def send_notification
    # Send notification to user(s)
    user_ids = params[:user_ids] || [ params[:user_id] ]
    message = params[:message]
    notification_type = params[:type] || "info"

    user = User.find_by(id: user_ids.compact.first)

    notifications = user_ids.compact.map do |uid|
      u = User.find_by(id: uid)
      Notification.create(
        user_id: uid,
        account_id: u&.account_id,
        title: params[:title] || message.to_s.truncate(100),
        message: message,
        notification_type: notification_type,
        severity: params[:severity] || "info",
        category: params[:category] || "general",
        read_at: nil
      )
    end

    render_success(
      data: notifications.map { |n| notification_data(n) },
      message: "Notifications sent"
    )
  end

  # POST /api/v1/internal/notifications/security_alert
  def security_alert
    # Send security alert notification
    user_id = params[:user_id]
    account_id = params[:account_id]
    alert_type = params[:alert_type]
    message = params[:message]
    severity = params[:severity] || "warning"

    notification = Notification.create(
      user_id: user_id,
      account_id: account_id,
      title: params[:title] || "Security Alert: #{alert_type}",
      message: message,
      notification_type: "security_alert",
      severity: severity,
      category: "security",
      metadata: { alert_type: alert_type, severity: severity },
      read_at: nil
    )

    render_success(data: notification_data(notification), message: "Security alert sent")
  end

  private

  def notification_params
    params.permit(:user_id, :account_id, :message, :notification_type, :title, :severity, :category, :metadata)
  end

  def notification_data(notification)
    {
      id: notification.id,
      user_id: notification.user_id,
      message: notification.message,
      notification_type: notification.notification_type,
      read: notification.read?,
      created_at: notification.created_at
    }
  end
end
