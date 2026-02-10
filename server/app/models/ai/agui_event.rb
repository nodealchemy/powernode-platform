# frozen_string_literal: true

module Ai
  class AguiEvent < ApplicationRecord
    self.table_name = "ai_agui_events"

    # ==========================================
    # Constants — AG-UI Protocol Event Types
    # ==========================================
    EVENT_TYPES = %w[
      TEXT_MESSAGE_START
      TEXT_MESSAGE_CONTENT
      TEXT_MESSAGE_END
      TOOL_CALL_START
      TOOL_CALL_ARGS
      TOOL_CALL_END
      TOOL_CALL_RESULT
      STATE_SNAPSHOT
      STATE_DELTA
      MESSAGES_SNAPSHOT
      ACTIVITY_SNAPSHOT
      ACTIVITY_DELTA
      RUN_STARTED
      RUN_FINISHED
      RUN_ERROR
      STEP_STARTED
      STEP_FINISHED
      CUSTOM
      RAW
    ].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :session, class_name: "Ai::AguiSession", foreign_key: :session_id
    belongs_to :account

    # ==========================================
    # Validations
    # ==========================================
    validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
    validates :sequence_number, presence: true,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 },
              uniqueness: { scope: :session_id }

    # ==========================================
    # Scopes
    # ==========================================
    scope :ordered, -> { order(sequence_number: :asc) }
    scope :by_type, ->(type) { where(event_type: type) }
    scope :text_events, -> { where(event_type: %w[TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END]) }
    scope :tool_events, -> { where(event_type: %w[TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END TOOL_CALL_RESULT]) }
    scope :state_events, -> { where(event_type: %w[STATE_SNAPSHOT STATE_DELTA]) }
    scope :lifecycle_events, -> { where(event_type: %w[RUN_STARTED RUN_FINISHED RUN_ERROR]) }
    scope :step_events, -> { where(event_type: %w[STEP_STARTED STEP_FINISHED]) }
    scope :after_sequence, ->(seq) { where("sequence_number > ?", seq) }
    scope :recent, -> { order(created_at: :desc) }

    # ==========================================
    # Public Methods
    # ==========================================

    def text_event?
      event_type.start_with?("TEXT_MESSAGE")
    end

    def tool_event?
      event_type.start_with?("TOOL_CALL")
    end

    def state_event?
      event_type.in?(%w[STATE_SNAPSHOT STATE_DELTA])
    end

    def lifecycle_event?
      event_type.in?(%w[RUN_STARTED RUN_FINISHED RUN_ERROR])
    end

    def to_sse_data
      {
        type: event_type,
        sequence: sequence_number,
        message_id: message_id,
        tool_call_id: tool_call_id,
        role: role,
        content: content,
        delta: delta,
        metadata: metadata,
        run_id: run_id,
        step_id: step_id,
        timestamp: created_at&.iso8601
      }.compact
    end
  end
end
