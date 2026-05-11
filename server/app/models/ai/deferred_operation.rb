# frozen_string_literal: true

module Ai
  # Captures a mutating operation that may be auto-approved or deferred for
  # human approval via the AutonomyGate. Every operation gated through
  # `Ai::AutonomyGate.evaluate` produces a row here — auto-approved ones get
  # status: "approved" immediately and execute synchronously; pending ones
  # link to an `Ai::ApprovalRequest` and execute via the worker job once the
  # chain completes.
  class DeferredOperation < ApplicationRecord
    self.table_name = "ai_deferred_operations"

    include AASM

    STATUSES = %w[pending approved rejected expired executing completed failed].freeze

    belongs_to :account
    belongs_to :approval_request, class_name: "Ai::ApprovalRequest", optional: true
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :ai_agent, class_name: "Ai::Agent", optional: true

    validates :action_category, presence: true
    validates :executor_class,  presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :pending,    -> { where(status: "pending") }
    scope :approved,   -> { where(status: "approved") }
    scope :rejected,   -> { where(status: "rejected") }
    scope :completed,  -> { where(status: "completed") }
    scope :failed,     -> { where(status: "failed") }
    scope :for_source, ->(type, id) { where(source_type: type, source_id: id) }
    scope :recent,     -> { order(created_at: :desc) }

    aasm column: :status, whiny_transitions: true do
      state :pending, initial: true
      state :approved
      state :rejected
      state :expired
      state :executing
      state :completed
      state :failed

      event :approve do
        transitions from: :pending, to: :approved
      end

      event :reject do
        transitions from: :pending, to: :rejected
      end

      event :expire do
        transitions from: :pending, to: :expired
      end

      event :start_execution do
        transitions from: :approved, to: :executing
      end

      event :complete do
        transitions from: :executing, to: :completed
        before do |result_data = {}|
          self.result = result_data
          self.executed_at = Time.current
        end
      end

      event :fail do
        transitions from: %i[approved executing], to: :failed
        before do |error = nil|
          self.error_message = error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s
          self.executed_at ||= Time.current
        end
      end
    end

    # Polymorphic callback invoked from `Ai::ApprovalRequest#notify_source_of_decision`
    # when source_type == "Ai::DeferredOperation". Approval flips status and
    # invokes the executor synchronously; rejection/expiry terminates.
    #
    # Synchronous because executors live in the server process and most
    # operations are fast (record updates, model destroys). Long-running
    # ops (K3s bootstrap, etc.) should delegate to System::Task internally
    # so the actual work happens in the worker via the existing dispatch.
    def on_approval_decision(request)
      return unless pending?

      case request.status
      when "approved"
        execute_now!
      when "rejected"
        reject!
      when "expired"
        expire!
      end
    end

    # Synchronous execution. Used by AutonomyGate for auto-approved operations
    # (so the calling controller gets the result inline) and by
    # on_approval_decision after a chain completes. The result is captured in
    # :result JSONB; row transitions to :completed (or :failed) atomically.
    def execute_now!
      approve! if pending?
      start_execution!
      result_data = executor_constant.execute(params, deferred_operation: self)
      complete!(result_data || {})
      result_data
    rescue StandardError => e
      Rails.logger.error("[DeferredOperation##{id}] execute_now! failed: #{e.class}: #{e.message}")
      fail!(e) if may_fail?
      raise
    end

    def executor_constant
      @executor_constant ||= executor_class.constantize
    end

    def preview
      executor_constant.respond_to?(:preview) ? executor_constant.preview(params) : { summary: action_category }
    rescue StandardError => e
      { summary: action_category, error: "preview failed: #{e.message}" }
    end
  end
end
