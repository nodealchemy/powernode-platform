# frozen_string_literal: true

# Internal API for review notification operations
class Api::V1::Internal::ReviewNotificationsController < Api::V1::Internal::InternalBaseController

  # GET /api/v1/internal/review_notifications/:id
  def show
    notification = Review::Notification.find(params[:id])
    review = notification.review
    app = review.app

    render_success({
      id: notification.id,
      recipient_email: notification.recipient.email,
      recipient_name: notification.recipient.name,
      review: {
        id: review.id,
        rating: review.rating,
        title: review.title,
        comment: review.comment,
        author_name: review.user.name,
        created_at: review.created_at
      },
      app: {
        id: app.id,
        name: app.name,
        description: app.description
      },
      status: notification.status
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Review notification not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch review notification: #{e.message}"
    render_error("Failed to fetch notification", status: :internal_server_error)
  end

  # PATCH /api/v1/internal/review_notifications/:id
  def update
    notification = Review::Notification.find(params[:id])

    update_params = {}

    if params[:status]
      update_params[:status] = params[:status]

      case params[:status]
      when "sent"
        update_params[:sent_at] = params[:sent_at] || Time.current
      when "failed"
        update_params[:error_message] = params[:error_message]
      end
    end

    notification.update!(update_params)

    Rails.logger.info "Review notification status updated: #{notification.id} -> #{params[:status]}"

    render_success({
      id: notification.id,
      status: notification.status,
      message: "Notification status updated"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Review notification not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to update review notification: #{e.message}"
    render_error("Failed to update notification", status: :internal_server_error)
  end
end
