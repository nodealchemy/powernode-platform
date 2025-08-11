class WebhookDelivery < ApplicationRecord
  # Associations
  belongs_to :webhook_endpoint

  # Validations
  validates :event_type, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending successful failed max_retries_reached] }
  validates :attempt_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Serialization
  serialize :payload, coder: JSON
  serialize :response_headers, coder: JSON
  serialize :metadata, coder: JSON

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :successful, -> { where(status: 'successful') }
  scope :failed, -> { where(status: 'failed') }
  scope :max_retries_reached, -> { where(status: 'max_retries_reached') }
  scope :pending_retry, -> { where(status: 'failed').where('next_retry_at <= ?', Time.current) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_defaults
  after_update :update_webhook_endpoint_stats

  # Instance methods
  def successful?
    status == 'successful'
  end

  def failed?
    status == 'failed'
  end

  def pending?
    status == 'pending'
  end

  def max_retries_reached?
    status == 'max_retries_reached'
  end

  def can_retry?
    failed? && attempt_count < webhook_endpoint.retry_limit && next_retry_at <= Time.current
  end

  def mark_as_successful!(response_data = {})
    update!(
      status: 'successful',
      completed_at: Time.current,
      http_status: response_data[:http_status],
      response_time_ms: response_data[:response_time_ms],
      response_body: response_data[:response_body],
      response_headers: response_data[:response_headers] || {}
    )
  end

  def mark_as_failed!(error_data = {})
    self.attempt_count += 1
    
    if attempt_count >= webhook_endpoint.retry_limit
      self.status = 'max_retries_reached'
      self.next_retry_at = nil
    else
      self.status = 'failed'
      self.next_retry_at = calculate_next_retry_time
    end

    update!(
      completed_at: Time.current,
      error_message: error_data[:error_message],
      http_status: error_data[:http_status],
      response_time_ms: error_data[:response_time_ms],
      response_body: error_data[:response_body],
      response_headers: error_data[:response_headers] || {}
    )
  end

  def retry!
    return false unless can_retry?

    self.status = 'pending'
    self.next_retry_at = nil
    self.completed_at = nil
    save!
  end

  def duration_seconds
    return nil unless completed_at && created_at
    (completed_at - created_at).to_f
  end

  def retry_delay_seconds
    return nil unless next_retry_at && created_at
    (next_retry_at - created_at).to_f
  end

  private

  def set_defaults
    self.status ||= 'pending'
    self.attempt_count ||= 0
    self.payload ||= {}
    self.response_headers ||= {}
    self.metadata ||= {}
  end

  def calculate_next_retry_time
    case webhook_endpoint.retry_backoff
    when 'linear'
      attempt_count * 5.minutes.from_now
    when 'exponential'
      (2 ** attempt_count).minutes.from_now
    else
      5.minutes.from_now
    end
  end

  def update_webhook_endpoint_stats
    return unless saved_change_to_status?

    case status
    when 'successful'
      webhook_endpoint.increment!(:success_count)
      webhook_endpoint.update!(last_delivery_at: completed_at)
    when 'failed', 'max_retries_reached'
      webhook_endpoint.increment!(:failure_count)
    end
  end
end