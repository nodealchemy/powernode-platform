# frozen_string_literal: true

class WebhookDelivery < ApplicationRecord
  # Associations
  belongs_to :webhook_endpoint
  belongs_to :webhook_event

  # Validations
  validates :status, presence: true, inclusion: { in: %w[pending success failed timeout] }
  validates :attempt_number, presence: true, numericality: { greater_than: 0 }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "failed") }
  scope :timed_out, -> { where(status: "timeout") }
  scope :pending_retry, -> { where(status: "failed").where("next_retry_at <= ?", Time.current) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_defaults
  after_update :update_webhook_endpoint_stats

  # Instance methods
  def successful?
    status == "success"
  end

  def failed?
    status == "failed"
  end

  def pending?
    status == "pending"
  end

  def timed_out?
    status == "timeout"
  end

  def can_retry?
    failed? && attempt_number < webhook_endpoint.retry_limit && next_retry_at.present? && next_retry_at <= Time.current
  end

  def mark_as_successful!(response_data = {})
    update!(
      status: "success",
      attempted_at: Time.current,
      response_status: response_data[:response_status],
      response_body: response_data[:response_body],
      response_headers: response_data[:response_headers] || {}
    )
  end

  def mark_as_failed!(error_data = {})
    self.attempt_number += 1

    if attempt_number >= webhook_endpoint.retry_limit
      self.status = "timeout"
      self.next_retry_at = nil
    else
      self.status = "failed"
      self.next_retry_at = calculate_next_retry_time
    end

    update!(
      attempted_at: Time.current,
      error_message: error_data[:error_message],
      response_status: error_data[:response_status],
      response_body: error_data[:response_body],
      response_headers: error_data[:response_headers] || {}
    )
  end

  def retry!
    return false unless can_retry?

    self.status = "pending"
    self.next_retry_at = nil
    self.attempted_at = nil
    save!
  end

  def duration_seconds
    return nil unless attempted_at && created_at
    (attempted_at - created_at).to_f
  end

  def retry_delay_seconds
    return nil unless next_retry_at && created_at
    (next_retry_at - created_at).to_f
  end

  private

  def set_defaults
    self.status ||= "pending"
    self.attempt_number ||= 1
    self.request_headers ||= {}
    self.response_headers ||= {}
  end

  def calculate_next_retry_time
    case webhook_endpoint.retry_backoff
    when "linear"
      (attempt_number * 5).minutes.from_now
    when "exponential"
      (2 ** attempt_number).minutes.from_now
    else
      5.minutes.from_now
    end
  end

  def update_webhook_endpoint_stats
    return unless saved_change_to_status?

    case status
    when "success"
      webhook_endpoint.increment!(:success_count)
      webhook_endpoint.update!(last_delivery_at: attempted_at)
    when "failed", "timeout"
      webhook_endpoint.increment!(:failure_count)
    end
  end
end
