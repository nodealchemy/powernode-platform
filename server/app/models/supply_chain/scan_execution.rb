# frozen_string_literal: true

module SupplyChain
  class ScanExecution < ApplicationRecord
    include Auditable
    include ExecutionTrackable

    self.table_name = "supply_chain_scan_executions"

    # ============================================
    # Constants
    # ============================================
    STATUSES = %w[pending running completed failed cancelled].freeze
    TRIGGER_TYPES = %w[manual scheduled webhook pipeline api].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :scan_instance, class_name: "SupplyChain::ScanInstance"
    belongs_to :account
    belongs_to :triggered_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :execution_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :trigger_type, presence: true, inclusion: { in: TRIGGER_TYPES }

    # ============================================
    # Scopes
    # ============================================
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :finished, -> { where(status: %w[completed failed cancelled]) }
    scope :successful, -> { where(status: "completed") }
    scope :by_trigger, ->(type) { where(trigger_type: type) }
    scope :manual, -> { where(trigger_type: "manual") }
    scope :scheduled, -> { where(trigger_type: "scheduled") }
    scope :for_instance, ->(instance_id) { where(scan_instance_id: instance_id) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_execution_id, on: :create
    before_save :sanitize_jsonb_fields
    after_save :update_instance_stats, if: :saved_change_to_status?

    # ============================================
    # Instance Methods
    # ============================================
    def pending?
      status == "pending"
    end

    def running?
      status == "running"
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

    def finished?
      status.in?(%w[completed failed cancelled])
    end

    def successful?
      completed?
    end

    def manual?
      trigger_type == "manual"
    end

    def scheduled?
      trigger_type == "scheduled"
    end

    def formatted_duration
      return nil unless duration_ms.present?

      seconds = duration_ms / 1000
      minutes = seconds / 60

      if minutes > 0
        "#{minutes}m #{seconds % 60}s"
      else
        "#{seconds}s"
      end
    end

    def start!
      update!(
        status: "running",
        started_at: Time.current
      )
    end

    def complete!(output = {})
      update!(
        status: "completed",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        output_data: output
      )
    end

    def fail!(error)
      update!(
        status: "failed",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        error_message: error
      )
    end

    def cancel!
      update!(
        status: "cancelled",
        completed_at: Time.current,
        duration_ms: calculate_duration
      )
    end

    def append_log(message)
      timestamp = Time.current.iso8601
      new_logs = "#{logs}\n[#{timestamp}] #{message}".strip
      update!(logs: new_logs)
    end

    def template_name
      scan_instance.scan_template.name
    end

    def instance_name
      scan_instance.name
    end

    def summary
      {
        id: id,
        execution_id: execution_id,
        scan_instance_id: scan_instance_id,
        instance_name: instance_name,
        template_name: template_name,
        status: status,
        trigger_type: trigger_type,
        triggered_by_id: triggered_by_id,
        started_at: started_at,
        completed_at: completed_at,
        duration_ms: duration_ms,
        formatted_duration: formatted_duration,
        successful: successful?,
        error_message: error_message,
        created_at: created_at
      }
    end

    def detailed_execution
      {
        summary: summary,
        input_data: input_data,
        output_data: output_data,
        logs: logs
      }
    end

    private

    def generate_execution_id
      return if execution_id.present?

      prefix = "exec"
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      random = SecureRandom.hex(4)
      self.execution_id = "#{prefix}-#{timestamp}-#{random}"
    end

    def sanitize_jsonb_fields
      self.input_data ||= {}
      self.output_data ||= {}
      self.metadata ||= {}
    end

    def calculate_duration
      return nil unless started_at.present?

      ((Time.current - started_at) * 1000).to_i
    end

    def update_instance_stats
      return unless finished?

      scan_instance.record_execution_result!(success: successful?)
    end
  end
end
