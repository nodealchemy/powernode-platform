# frozen_string_literal: true

# Metrics tracking for worker jobs
module MetricsTracking
  extend ActiveSupport::Concern

  included do
    around_execute :track_job_metrics
  end

  private

  def track_job_metrics
    start_time = Time.current
    job_class = self.class.name
    queue = self.class.queue_name
    
    begin
      yield
      track_job_completion(job_class, 'success', queue, Time.current - start_time)
    rescue => e
      track_job_completion(job_class, 'failure', queue, Time.current - start_time)
      track_job_error(job_class, queue, e)
      raise e
    end
  end

  def track_job_completion(job_class, status, queue, duration)
    # Send metrics to backend API for Prometheus collection
    BackendApiClient.post('/api/v1/internal/metrics/jobs', {
      job_class: job_class,
      status: status,
      queue: queue,
      duration_seconds: duration,
      timestamp: Time.current.iso8601
    })
  rescue => e
    logger.error "Failed to track job metrics: #{e.message}"
  end

  def track_job_error(job_class, queue, error)
    # Track error details
    BackendApiClient.post('/api/v1/internal/metrics/errors', {
      job_class: job_class,
      queue: queue,
      error_class: error.class.name,
      error_message: error.message.truncate(255),
      timestamp: Time.current.iso8601
    })
  rescue => e
    logger.error "Failed to track job error: #{e.message}"
  end

  # Track custom business metrics from jobs
  def track_business_metric(metric_name, value, labels = {})
    BackendApiClient.post('/api/v1/internal/metrics/custom', {
      metric_name: metric_name,
      value: value,
      labels: labels,
      timestamp: Time.current.iso8601
    })
  rescue => e
    logger.error "Failed to track business metric: #{e.message}"
  end

  # Helper methods for common metrics
  def track_subscription_event(subscription_id, event_type)
    track_business_metric('subscription_events', 1, {
      subscription_id: subscription_id,
      event_type: event_type
    })
  end

  def track_payment_processing(payment_id, provider, amount_cents, status)
    track_business_metric('payment_processing', 1, {
      payment_id: payment_id,
      provider: provider,
      amount_cents: amount_cents,
      status: status
    })
  end

  def track_notification_sent(notification_type, channel, recipient_count = 1)
    track_business_metric('notifications_sent', recipient_count, {
      notification_type: notification_type,
      channel: channel
    })
  end

  def track_webhook_processing(webhook_id, provider, event_type, status)
    track_business_metric('webhook_processing', 1, {
      webhook_id: webhook_id,
      provider: provider,
      event_type: event_type,
      status: status
    })
  end
end