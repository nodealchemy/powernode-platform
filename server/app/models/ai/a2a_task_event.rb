# frozen_string_literal: true

module Ai
  class A2aTaskEvent < ApplicationRecord
    # ==================== Constants ====================
    EVENT_TYPES = %w[status_change artifact_added message progress error cancelled].freeze

    # ==================== Associations ====================
    belongs_to :a2a_task, class_name: "Ai::A2aTask", foreign_key: "ai_a2a_task_id"

    # ==================== Validations ====================
    validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

    # ==================== Scopes ====================
    scope :status_changes, -> { where(event_type: "status_change") }
    scope :artifacts, -> { where(event_type: "artifact_added") }
    scope :messages, -> { where(event_type: "message") }
    scope :progress_events, -> { where(event_type: "progress") }
    scope :errors, -> { where(event_type: "error") }
    scope :recent, -> { order(created_at: :desc) }
    scope :chronological, -> { order(created_at: :asc) }
    scope :since, ->(timestamp) { where("created_at > ?", timestamp) }

    # ==================== Callbacks ====================
    before_validation :generate_event_id, on: :create
    after_create :broadcast_event

    # ==================== Instance Methods ====================

    # Format for A2A SSE streaming
    def to_sse_json
      {
        id: event_id,
        type: sse_event_type,
        data: sse_data
      }
    end

    # Generate A2A-compliant event format
    def to_a2a_json
      base = {
        id: event_id,
        type: event_type,
        timestamp: created_at.iso8601,
        taskId: a2a_task.task_id
      }

      case event_type
      when "status_change"
        base.merge(
          previous: previous_status,
          current: new_status
        )
      when "artifact_added"
        base.merge(
          artifactId: artifact_id,
          name: artifact_name,
          mimeType: artifact_mime_type
        )
      when "progress"
        base.merge(
          current: progress_current,
          total: progress_total,
          message: progress_message
        )
      when "error"
        base.merge(
          error: data
        )
      when "message"
        base.merge(
          message: message || data["message"]
        )
      when "cancelled"
        base.merge(
          reason: data["reason"]
        )
      else
        base.merge(data: data)
      end.compact
    end

    # Event summary
    def event_summary
      {
        id: id,
        event_id: event_id,
        event_type: event_type,
        created_at: created_at,
        message: message || data["message"]
      }
    end

    # Check event type helpers
    def status_change?
      event_type == "status_change"
    end

    def artifact_added?
      event_type == "artifact_added"
    end

    def progress_event?
      event_type == "progress"
    end

    def error_event?
      event_type == "error"
    end

    # Progress percentage
    def progress_percentage
      return nil unless progress_event? && progress_total.present? && progress_total.positive?

      ((progress_current.to_f / progress_total) * 100).round(1)
    end

    private

    def generate_event_id
      self.event_id ||= "evt_#{SecureRandom.hex(8)}"
    end

    def sse_event_type
      case event_type
      when "status_change" then "task.status"
      when "artifact_added" then "task.artifact"
      when "progress" then "task.progress"
      when "error" then "task.error"
      when "message" then "task.message"
      when "cancelled" then "task.cancelled"
      else "task.event"
      end
    end

    def sse_data
      to_a2a_json.except(:id, :type).to_json
    end

    def broadcast_event
      channel_key = "a2a_task_#{a2a_task.task_id}"

      ActionCable.server.broadcast(
        channel_key,
        to_sse_json
      )

      # Also broadcast to account channel
      account_channel = "account_#{a2a_task.account_id}"
      McpChannel.broadcast_to(
        account_channel,
        {
          type: "a2a_task_event",
          task_id: a2a_task.task_id,
          event: to_a2a_json
        }
      )
    end
  end
end
