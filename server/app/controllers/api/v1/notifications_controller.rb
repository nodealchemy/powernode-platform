# frozen_string_literal: true

class Api::V1::NotificationsController < ApplicationController
  before_action :set_notification, only: [:show, :mark_as_read, :mark_as_unread, :dismiss]

  # GET /api/v1/notifications
  def index
    notifications = current_user.notifications.active.recent

    # Apply filters
    notifications = notifications.unread if params[:unread] == 'true'
    notifications = notifications.by_category(params[:category]) if params[:category].present?
    notifications = notifications.by_type(params[:type]) if params[:type].present?

    # Pagination
    page = (params[:page] || 1).to_i
    per_page = [(params[:per_page] || 20).to_i, 100].min

    total_count = notifications.count
    notifications = notifications.limit(per_page).offset((page - 1) * per_page)

    render_success(
      data: {
        notifications: notifications.map { |n| notification_data(n) },
        unread_count: current_user.notifications.active.unread.count,
        pagination: {
          current_page: page,
          per_page: per_page,
          total_count: total_count,
          total_pages: (total_count.to_f / per_page).ceil
        }
      }
    )
  end

  # GET /api/v1/notifications/unread_count
  def unread_count
    count = current_user.notifications.active.unread.count

    render_success(
      data: { unread_count: count }
    )
  end

  # GET /api/v1/notifications/:id
  def show
    render_success(
      data: notification_data(@notification)
    )
  end

  # PUT /api/v1/notifications/:id/read
  def mark_as_read
    @notification.mark_as_read!

    render_success(
      message: "Notification marked as read",
      data: notification_data(@notification)
    )
  end

  # PUT /api/v1/notifications/:id/unread
  def mark_as_unread
    @notification.mark_as_unread!

    render_success(
      message: "Notification marked as unread",
      data: notification_data(@notification)
    )
  end

  # POST /api/v1/notifications/mark_all_read
  def mark_all_read
    count = current_user.notifications.active.unread.update_all(read_at: Time.current)

    render_success(
      message: "#{count} notifications marked as read",
      data: { marked_count: count }
    )
  end

  # DELETE /api/v1/notifications/:id
  def dismiss
    @notification.dismiss!

    render_success(
      message: "Notification dismissed"
    )
  end

  # DELETE /api/v1/notifications/dismiss_all
  def dismiss_all
    count = current_user.notifications.active.update_all(dismissed_at: Time.current)

    render_success(
      message: "#{count} notifications dismissed",
      data: { dismissed_count: count }
    )
  end

  private

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Notification not found", status: :not_found)
  end

  def notification_data(notification)
    {
      id: notification.id,
      type: notification.notification_type,
      title: notification.title,
      message: notification.message,
      severity: notification.severity,
      action_url: notification.action_url,
      action_label: notification.action_label,
      icon: notification.icon,
      category: notification.category,
      metadata: notification.metadata,
      read: notification.read?,
      read_at: notification.read_at,
      expires_at: notification.expires_at,
      created_at: notification.created_at
    }
  end
end
