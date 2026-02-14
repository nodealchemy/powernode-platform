# frozen_string_literal: true

module Ai
  class A2aTask < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable

    # ==================== Constants ====================
    STATUSES = %w[pending active completed failed cancelled input_required].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze

    # A2A Message Roles
    MESSAGE_ROLES = %w[user agent].freeze

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :from_agent, class_name: "Ai::Agent", foreign_key: "from_agent_id", optional: true
    belongs_to :to_agent, class_name: "Ai::Agent", foreign_key: "to_agent_id", optional: true
    belongs_to :from_agent_card, class_name: "Ai::AgentCard", foreign_key: "from_agent_card_id", optional: true
    belongs_to :to_agent_card, class_name: "Ai::AgentCard", foreign_key: "to_agent_card_id", optional: true
    belongs_to :workflow_run, class_name: "Ai::WorkflowRun", foreign_key: "ai_workflow_run_id", optional: true
    belongs_to :parent_task, class_name: "Ai::A2aTask", foreign_key: "parent_task_id", optional: true

    has_many :subtasks, class_name: "Ai::A2aTask", foreign_key: "parent_task_id", dependent: :destroy
    has_many :events, class_name: "Ai::A2aTaskEvent", foreign_key: "ai_a2a_task_id", dependent: :destroy

    # ==================== Validations ====================
    validates :task_id, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :retry_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :max_retries, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    validate :validate_message_format
    validate :validate_at_least_one_target

    # ==================== Scopes ====================
    scope :pending, -> { where(status: "pending") }
    scope :active, -> { where(status: "active") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :input_required, -> { where(status: "input_required") }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :in_progress, -> { where(status: %w[pending active input_required]) }
    scope :for_workflow_run, ->(run_id) { where(ai_workflow_run_id: run_id) }
    scope :from_agent, ->(agent_id) { where(from_agent_id: agent_id) }
    scope :to_agent, ->(agent_id) { where(to_agent_id: agent_id) }
    scope :external_tasks, -> { where(is_external: true) }
    scope :internal_tasks, -> { where(is_external: false) }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_sequence, -> { order(sequence_number: :asc) }

    # ==================== Callbacks ====================
    before_validation :generate_task_id, on: :create
    before_validation :set_sequence_number, on: :create
    before_save :calculate_duration, if: -> { completed_at_changed? && completed_at.present? }
    after_save :record_status_change, if: :saved_change_to_status?
    after_save :update_agent_card_metrics, if: :terminal?
    after_save :broadcast_task_update

    # ==================== State Machine Methods ====================

    def start!
      raise InvalidTransitionError, "Cannot start task in #{status} status" unless can_start?

      update!(
        status: "active",
        started_at: Time.current
      )

      record_event("status_change", { previous: "pending", new: "active" })
    end

    def complete!(result: {}, artifacts: [])
      raise InvalidTransitionError, "Cannot complete task in #{status} status" unless can_complete?

      self.output = result
      self.artifacts = (self.artifacts || []) + artifacts
      self.status = "completed"
      self.completed_at = Time.current

      save!
      record_event("status_change", { previous: status_before_last_save, new: "completed", output: result })
    end

    def fail!(error_message:, error_code: nil, error_details: {})
      raise InvalidTransitionError, "Cannot fail task in #{status} status" unless can_fail?

      update!(
        status: "failed",
        completed_at: Time.current,
        error_message: error_message,
        error_code: error_code,
        error_details: error_details
      )

      record_event("error", {
        message: error_message,
        code: error_code,
        details: error_details
      })
    end

    def cancel!(reason: nil)
      raise InvalidTransitionError, "Cannot cancel task in #{status} status" unless can_cancel?

      update!(
        status: "cancelled",
        completed_at: Time.current,
        metadata: metadata.merge("cancellation_reason" => reason)
      )

      record_event("cancelled", { reason: reason })
    end

    def request_input!(prompt:, schema: nil)
      raise InvalidTransitionError, "Cannot request input in #{status} status" unless can_request_input?

      update!(
        status: "input_required",
        output: output.merge(
          "input_request" => {
            "prompt" => prompt,
            "schema" => schema,
            "requested_at" => Time.current.iso8601
          }
        )
      )

      record_event("status_change", { previous: status_before_last_save, new: "input_required", prompt: prompt })
    end

    def provide_input!(input_data)
      raise InvalidTransitionError, "Cannot provide input in #{status} status" unless status == "input_required"

      # Add to history and continue
      add_to_history(role: "user", content: input_data)
      update!(status: "active")

      record_event("status_change", { previous: "input_required", new: "active", input_provided: true })
    end

    def retry!
      raise InvalidTransitionError, "Cannot retry task in #{status} status" unless can_retry?
      raise RetryLimitExceeded, "Max retries (#{max_retries}) exceeded" if retry_count >= max_retries

      update!(
        status: "pending",
        retry_count: retry_count + 1,
        error_message: nil,
        error_code: nil,
        error_details: {},
        started_at: nil,
        completed_at: nil
      )

      record_event("status_change", { previous: "failed", new: "pending", retry_count: retry_count })
    end

    # ==================== State Checks ====================

    def can_start?
      status == "pending"
    end

    def can_complete?
      status.in?(%w[active input_required])
    end

    def can_fail?
      status.in?(%w[pending active input_required])
    end

    def can_cancel?
      !terminal?
    end

    def can_request_input?
      status == "active"
    end

    def can_retry?
      status == "failed" && retry_count < max_retries
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def in_progress?
      !terminal?
    end

    # ==================== A2A Protocol Methods ====================

    # Generate A2A-compliant task response
    def to_a2a_json
      {
        id: task_id,
        sessionId: workflow_run&.run_id,
        status: a2a_status,
        artifacts: a2a_artifacts,
        history: history
      }.tap do |json|
        json[:message] = message if message.present?
        json[:error] = a2a_error if status == "failed"
        # Include timestamps in metadata for A2A protocol compliance
        json[:metadata] = a2a_metadata
      end
    end

    # Build A2A-compliant metadata including timestamps
    def a2a_metadata
      base_metadata = metadata || {}
      base_metadata.merge(
        "submitted_at" => created_at&.iso8601,
        "started_at" => started_at&.iso8601,
        "completed_at" => completed_at&.iso8601,
        "from_agent_id" => from_agent_id,
        "to_agent_id" => to_agent_id,
        "workflow_run_id" => ai_workflow_run_id,
        "is_external" => is_external,
        "retry_count" => retry_count
      ).compact
    end

    # A2A status mapping
    def a2a_status
      case status
      when "pending" then { state: "submitted" }
      when "active" then { state: "working" }
      when "completed" then { state: "completed" }
      when "failed" then { state: "failed" }
      when "cancelled" then { state: "canceled" }
      when "input_required" then { state: "input-required" }
      else { state: "unknown" }
      end
    end

    # Format artifacts for A2A
    def a2a_artifacts
      (artifacts || []).map do |artifact|
        {
          id: artifact["id"] || SecureRandom.uuid,
          name: artifact["name"],
          mimeType: artifact["mime_type"] || artifact["mimeType"],
          uri: artifact["uri"],
          parts: artifact["parts"] || [ { type: "text", text: artifact["content"] } ]
        }.compact
      end
    end

    # Format error for A2A
    def a2a_error
      return nil unless status == "failed"

      {
        code: error_code || "EXECUTION_ERROR",
        message: error_message,
        details: error_details
      }.compact
    end

    # Add message to history
    def add_to_history(role:, content:, parts: nil)
      message_entry = {
        "role" => role,
        "parts" => parts || [ { "type" => "text", "text" => content.to_s } ],
        "timestamp" => Time.current.iso8601
      }

      self.history = (history || []) + [ message_entry ]
      save!
    end

    # Add artifact
    def add_artifact(name:, content: nil, uri: nil, mime_type: "text/plain", parts: nil)
      artifact = {
        "id" => SecureRandom.uuid,
        "name" => name,
        "mime_type" => mime_type,
        "uri" => uri,
        "parts" => parts || (content ? [ { "type" => "text", "text" => content } ] : []),
        "created_at" => Time.current.iso8601
      }.compact

      self.artifacts = (artifacts || []) + [ artifact ]
      save!

      record_event("artifact_added", {
        artifact_id: artifact["id"],
        name: name,
        mime_type: mime_type
      })

      artifact
    end

    # ==================== Summary Methods ====================

    def task_summary
      {
        id: id,
        task_id: task_id,
        status: status,
        from_agent_id: from_agent_id,
        to_agent_id: to_agent_id,
        workflow_run_id: ai_workflow_run_id,
        is_external: is_external,
        duration_ms: duration_ms,
        created_at: created_at,
        started_at: started_at,
        completed_at: completed_at
      }
    end

    def task_details
      task_summary.merge(
        message: message,
        input: input,
        output: output,
        artifacts: artifacts,
        history: history,
        error_message: error_message,
        error_code: error_code,
        error_details: error_details,
        retry_count: retry_count,
        tokens_used: tokens_used,
        cost: cost,
        metadata: metadata
      )
    end

    # ==================== Custom Errors ====================

    class InvalidTransitionError < StandardError; end
    class RetryLimitExceeded < StandardError; end

    private

    def generate_task_id
      self.task_id ||= "task_#{SecureRandom.hex(12)}"
    end

    def set_sequence_number
      return unless ai_workflow_run_id.present? && sequence_number.nil?

      max_sequence = Ai::A2aTask.where(ai_workflow_run_id: ai_workflow_run_id).maximum(:sequence_number) || 0
      self.sequence_number = max_sequence + 1
    end

    def calculate_duration
      return unless started_at.present? && completed_at.present?

      self.duration_ms = ((completed_at - started_at) * 1000).to_i
    end

    def validate_message_format
      return if message.blank?

      unless message.is_a?(Hash)
        errors.add(:message, "must be a hash/object")
        return
      end

      if message["role"].present? && !MESSAGE_ROLES.include?(message["role"])
        errors.add(:message, "role must be one of: #{MESSAGE_ROLES.join(', ')}")
      end
    end

    def validate_at_least_one_target
      if to_agent_id.blank? && to_agent_card_id.blank? && !is_external
        errors.add(:base, "Task must have a target agent, agent card, or be external")
      end
    end

    def record_event(event_type, data)
      events.create!(
        event_type: event_type,
        event_id: "evt_#{SecureRandom.hex(8)}",
        data: data,
        previous_status: data[:previous],
        new_status: data[:new]
      )
    end

    def record_status_change
      # Status change is recorded in the state transition methods
    end

    def update_agent_card_metrics
      to_agent_card&.refresh_metrics!
    end

    def broadcast_task_update
      channel_key = "account_#{account_id}"

      McpChannel.broadcast_to(
        channel_key,
        {
          type: "a2a_task_update",
          task_id: task_id,
          status: status,
          workflow_run_id: workflow_run&.run_id
        }
      )
    end
  end
end
