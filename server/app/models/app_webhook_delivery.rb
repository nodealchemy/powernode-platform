# frozen_string_literal: true

class AppWebhookDelivery < ApplicationRecord
  # Associations
  belongs_to :app_webhook

  # Validations
  validates :delivery_id, presence: true, uniqueness: true
  validates :event_id, presence: true
  validates :status, presence: true, inclusion: { 
    in: %w[pending delivered failed cancelled],
    message: "must be pending, delivered, failed, or cancelled"
  }
  validates :attempt_number, presence: true, numericality: { greater_than: 0 }

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :delivered, -> { where(status: 'delivered') }
  scope :failed, -> { where(status: 'failed') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_retry, -> { where(status: 'pending').where('next_retry_at <= ?', Time.current) }
  scope :last_24h, -> { where('created_at > ?', 24.hours.ago) }
  scope :last_7d, -> { where('created_at > ?', 7.days.ago) }

  # Callbacks
  after_update :schedule_retry, if: :should_schedule_retry?

  # Instance methods
  def pending?
    status == 'pending'
  end

  def delivered?
    status == 'delivered'
  end

  def failed?
    status == 'failed'
  end

  def cancelled?
    status == 'cancelled'
  end

  def successful?
    delivered? && (200..299).include?(status_code.to_i)
  end

  def can_retry?
    (pending? || failed?) && attempt_number < app_webhook.max_retries
  end

  def ready_for_retry?
    can_retry? && (next_retry_at.nil? || next_retry_at <= Time.current)
  end

  def response_time_seconds
    return 0 unless response_time_ms
    response_time_ms / 1000.0
  end

  def mark_as_delivered!(response_code, response_time, response_body = nil, response_headers = {})
    update!(
      status: 'delivered',
      status_code: response_code,
      response_time_ms: response_time,
      response_body: response_body,
      response_headers: response_headers,
      delivered_at: Time.current,
      next_retry_at: nil
    )
  end

  def mark_as_failed!(error_msg, response_code = nil, response_time = nil, response_body = nil)
    new_status = can_retry? ? 'pending' : 'failed'
    
    update!(
      status: new_status,
      status_code: response_code,
      response_time_ms: response_time,
      response_body: response_body,
      error_message: error_msg,
      next_retry_at: new_status == 'pending' ? calculate_next_retry : nil
    )
  end

  def increment_attempt!
    update!(attempt_number: attempt_number + 1)
  end

  def cancel!
    update!(
      status: 'cancelled',
      next_retry_at: nil
    )
  end

  def app
    app_webhook.app
  end

  # Class methods
  def self.grouped_by_status
    group(:status).count
  end

  def self.success_rate
    total = count
    return 0 if total.zero?
    
    successful_count = delivered.count
    ((successful_count.to_f / total) * 100).round(2)
  end

  def self.average_response_time
    delivered.where.not(response_time_ms: nil)
             .average(:response_time_ms)&.to_f&.round(2) || 0
  end

  def self.retry_stats
    {
      total_retries: where('attempt_number > 1').count,
      max_attempts: maximum(:attempt_number) || 0,
      avg_attempts: average(:attempt_number)&.to_f&.round(2) || 0
    }
  end

  private

  def should_schedule_retry?
    saved_change_to_status? && status == 'pending' && attempt_number > 1
  end

  def schedule_retry
    # Schedule retry using background job
    WebhookRetryJob.perform_at(next_retry_at, id) if next_retry_at
  end

  def calculate_next_retry
    retry_config = app_webhook.retry_config_json
    backoff_type = retry_config['backoff_type'] || 'exponential'
    initial_delay = retry_config['initial_delay'] || 1
    max_delay = retry_config['max_delay'] || 300

    case backoff_type
    when 'linear'
      delay = initial_delay * attempt_number
    when 'exponential'
      delay = initial_delay * (2 ** (attempt_number - 1))
    when 'fixed'
      delay = initial_delay
    else
      delay = initial_delay * (2 ** (attempt_number - 1))
    end

    # Cap the delay at max_delay
    delay = [delay, max_delay].min
    
    Time.current + delay.seconds
  end
end