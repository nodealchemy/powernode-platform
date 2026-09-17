# frozen_string_literal: true

class WebhookDelivery < ApplicationRecord
  # Associations
  belongs_to :webhook_endpoint
  belongs_to :webhook_event

  # Validations
  validates :status, presence: true, inclusion: { in: %w[pending success failed timeout] }
  validates :attempt_number, presence: true, numericality: { greater_than: 0 }

  # Set by WebhookEventPublisher#deliver_to for a rate-limited delivery that
  # was recorded "failed" WITHOUT ever being attempted (IMP-dd0305de2799, D2):
  # the endpoint's success/failure stats must not treat a delivery that never
  # reached the network as a real failure. Checked by
  # #update_webhook_endpoint_stats below. Not persisted — a per-instance
  # signal for the one write that sets it.
  attr_accessor :skip_endpoint_stats

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

  # IMP-dd0305de2799 (D1): enqueuing here — after_commit, not at creation time
  # inside WebhookEventPublisher — is what keeps the worker from ever being
  # told about a delivery before it durably exists (or after its creating
  # transaction rolled back). WebhookEventPublisher.deliver_to runs inside
  # Auditable#write_audit_log, itself inside the after_create/after_update/
  # before_destroy callback of whatever real change triggered it — i.e. inside
  # THAT transaction, not this row's own. A synchronous enqueue there would
  # race the worker's internal delivery-fetch GET against that outer commit:
  # a 404 there is not treated as a failure or a reason to retry
  # (webhook_delivery_job.rb has no such branch), so the row would stay
  # "pending" forever and the event would be lost with no trace — the exact
  # failure class this producer exists to fix. after_commit also means a rolled-
  # back transaction (or Account#destroy's N cascaded user deletions, each
  # writing a WebhookDelivery inside one destroy transaction) never fires a
  # premature or orphaned enqueue.
  #
  # Fires once per row (on: :create only) and reads `status` as of COMMIT
  # time, not creation time: the rate-limited path in
  # WebhookEventPublisher#deliver_to updates the same in-memory record to
  # "failed" before the transaction commits, so this correctly skips
  # enqueuing for that path without needing a second flag.
  after_commit :enqueue_worker_job, on: :create

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

  # Next retry time honoring the endpoint's CONFIGURED retry_backoff, or nil once
  # the configured retry_limit is exhausted. The failure-recording path (worker
  # callback) uses this so a failed delivery is rescheduled with the
  # user-configured backoff instead of dropping it (leaving next_retry_at unset).
  def next_scheduled_retry_at
    return nil if attempt_number >= webhook_endpoint.retry_limit

    calculate_next_retry_time
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
    return if skip_endpoint_stats
    return unless saved_change_to_status?

    case status
    when "success"
      webhook_endpoint.increment!(:success_count)
      webhook_endpoint.update!(last_delivery_at: attempted_at)
    when "failed", "timeout"
      webhook_endpoint.increment!(:failure_count)
    end
  end

  # See the after_commit declaration above for why this fires here rather
  # than at creation time. Dispatches through the same worker HTTP-dispatch
  # seam (WorkerApiClient) Api::V1::WebhooksController#retry_failed /
  # #retry_delivery already use to reach Webhooks::WebhookDeliveryJob's
  # sibling, Webhooks::WebhookRetryJob.
  def enqueue_worker_job
    return unless status == "pending"

    WorkerApiClient.new.queue_job("Webhooks::WebhookDeliveryJob", [ id ], queue: "webhooks")
  rescue WorkerApiClient::ApiError => e
    Rails.logger.error "[WebhookDelivery] Failed to enqueue delivery #{id}: #{e.message}"
  end
end
