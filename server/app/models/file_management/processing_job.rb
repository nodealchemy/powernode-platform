# frozen_string_literal: true

module FileManagement
  class ProcessingJob < ApplicationRecord
    include Auditable

    # Associations
    belongs_to :object, class_name: "FileManagement::Object", foreign_key: :file_object_id
    belongs_to :account

    # Validations
    validates :job_type, presence: true, inclusion: {
      in: %w[thumbnail resize convert scan ocr metadata_extract compress watermark transform],
      message: "must be a valid job type"
    }
    validates :status, presence: true, inclusion: {
      in: %w[pending processing completed failed cancelled],
      message: "must be a valid status"
    }
    validates :priority, presence: true, numericality: {
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    }
    validates :retry_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :max_retries, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :validate_retry_limit

    # JSON columns
    attribute :job_parameters, :json, default: -> { {} }
    attribute :result_data, :json, default: -> { {} }
    attribute :error_details, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :processing, -> { where(status: "processing") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :active, -> { where(status: %w[pending processing]) }
    scope :finished, -> { where(status: %w[completed failed cancelled]) }
    scope :by_priority, -> { order(priority: :desc, created_at: :asc) }
    scope :by_type, ->(type) { where(job_type: type) }
    scope :recent, -> { order(created_at: :desc) }
    scope :retriable, -> { failed.where("retry_count < max_retries") }

    # Callbacks
    before_validation :set_defaults, on: :create

    # Status methods
    def pending?
      status == "pending"
    end

    def processing?
      status == "processing"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def cancelled?
      status == "cancelled"
    end

    def active?
      %w[pending processing].include?(status)
    end

    def finished?
      %w[completed failed cancelled].include?(status)
    end

    # Execution methods
    def start_processing!
      return false unless pending?

      update!(
        status: "processing",
        started_at: Time.current,
        metadata: metadata.merge("processing_started_at" => Time.current.iso8601)
      )
    end

    def mark_completed!(result = {})
      return false unless processing?

      duration = started_at ? ((Time.current - started_at) * 1000).to_i : 0

      update!(
        status: "completed",
        completed_at: Time.current,
        duration_ms: duration,
        result_data: result_data.merge(result),
        metadata: metadata.merge("completed_at" => Time.current.iso8601)
      )
    end

    def mark_failed!(error_message, error_data = {})
      return false unless processing?

      duration = started_at ? ((Time.current - started_at) * 1000).to_i : 0

      update!(
        status: "failed",
        completed_at: Time.current,
        duration_ms: duration,
        error_details: error_details.merge({
          "error_message" => error_message,
          "failed_at" => Time.current.iso8601
        }.merge(error_data)),
        metadata: metadata.merge("failed_at" => Time.current.iso8601)
      )
    end

    def cancel!
      return false if finished?

      update!(
        status: "cancelled",
        completed_at: Time.current,
        metadata: metadata.merge("cancelled_at" => Time.current.iso8601)
      )
    end

    # Retry management
    def can_retry?
      failed? && retry_count < max_retries
    end

    def retry!
      return false unless can_retry?

      transaction do
        increment!(:retry_count)

        update!(
          status: "pending",
          started_at: nil,
          completed_at: nil,
          error_details: {},
          metadata: metadata.merge({
            "retry_attempt" => retry_count,
            "retried_at" => Time.current.iso8601
          })
        )
      end

      true
    end

    def retries_remaining
      max_retries - retry_count
    end

    # Job parameter helpers
    def get_parameter(key)
      job_parameters[key.to_s]
    end

    def set_parameter(key, value)
      self.job_parameters = job_parameters.merge(key.to_s => value)
    end

    def get_result(key)
      result_data[key.to_s]
    end

    def set_result(key, value)
      self.result_data = result_data.merge(key.to_s => value)
      save
    end

    # Timing methods
    def execution_duration
      return nil unless started_at

      end_time = completed_at || Time.current
      end_time - started_at
    end

    def execution_duration_seconds
      execution_duration&.to_i
    end

    def execution_duration_ms
      return duration_ms if duration_ms.present?

      execution_duration ? (execution_duration * 1000).to_i : nil
    end

    # Summary
    def job_summary
      {
        id: id,
        job_type: job_type,
        status: status,
        priority: priority,
        file: object.filename,
        retry_count: retry_count,
        max_retries: max_retries,
        started_at: started_at&.iso8601,
        completed_at: completed_at&.iso8601,
        duration_ms: duration_ms,
        has_error: error_details.present?,
        error_message: error_details["error_message"],
        created_at: created_at.iso8601
      }
    end

    private

    def set_defaults
      self.priority ||= 50
      self.status ||= "pending"
      self.retry_count ||= 0
      self.max_retries ||= 3
      self.job_parameters ||= {}
      self.result_data ||= {}
      self.error_details ||= {}
      self.metadata ||= {}
    end

    def validate_retry_limit
      return unless retry_count.present? && max_retries.present?

      if retry_count > max_retries
        errors.add(:retry_count, "cannot exceed max_retries")
      end
    end
  end
end
