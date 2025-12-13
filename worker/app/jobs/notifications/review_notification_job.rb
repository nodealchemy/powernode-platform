# frozen_string_literal: true

# Review notification job - sends email notifications for new reviews
class Notifications::ReviewNotificationJob < BaseJob
  sidekiq_options queue: 'email', retry: 3

  def execute(review_notification_id)
    validate_required_params(review_notification_id: review_notification_id)

    log_info "Processing review notification: #{review_notification_id}"

    # Fetch notification details from backend
    notification_response = api_client.get("/api/v1/internal/review_notifications/#{review_notification_id}")

    unless notification_response['success']
      log_error "Failed to fetch notification: #{notification_response['error']}"
      return { success: false, error: notification_response['error'] }
    end

    notification_data = notification_response['data']
    recipient_email = notification_data['recipient_email']
    recipient_name = notification_data['recipient_name']
    review_data = notification_data['review']
    app_data = notification_data['app']

    log_info "Sending review notification to: #{recipient_email}"

    # Send email via backend email service
    email_result = send_review_email(
      recipient_email,
      recipient_name,
      review_data,
      app_data
    )

    if email_result[:success]
      # Mark notification as sent via API
      mark_notification_sent(review_notification_id)

      log_info "Review notification sent successfully: #{review_notification_id}"
      { success: true, notification_id: review_notification_id }
    else
      log_error "Failed to send review notification: #{email_result[:error]}"
      mark_notification_failed(review_notification_id, email_result[:error])
      { success: false, error: email_result[:error] }
    end
  rescue StandardError => e
    log_error "Review notification job failed: #{e.message}"
    mark_notification_failed(review_notification_id, e.message) rescue nil
    { success: false, error: e.message }
  end

  private

  def send_review_email(recipient_email, recipient_name, review_data, app_data)
    response = with_api_retry do
      api_client.post('/api/v1/internal/emails/review_notification', {
        recipient_email: recipient_email,
        recipient_name: recipient_name,
        review: review_data,
        app: app_data
      })
    end

    if response['success']
      { success: true }
    else
      { success: false, error: response['error'] || 'Email sending failed' }
    end
  end

  def mark_notification_sent(notification_id)
    with_api_retry do
      api_client.patch("/api/v1/internal/review_notifications/#{notification_id}", {
        status: 'sent',
        sent_at: Time.current.iso8601
      })
    end
  rescue StandardError => e
    log_error "Failed to mark notification as sent: #{e.message}"
  end

  def mark_notification_failed(notification_id, error_message)
    with_api_retry do
      api_client.patch("/api/v1/internal/review_notifications/#{notification_id}", {
        status: 'failed',
        error_message: error_message
      })
    end
  rescue StandardError => e
    log_error "Failed to mark notification as failed: #{e.message}"
  end
end
