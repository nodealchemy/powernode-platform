# frozen_string_literal: true

module Ai
  class ScheduledMessage < ApplicationRecord
    self.table_name = "ai_scheduled_messages"

    # Reuse scheduling logic from RalphLoop
    include Ai::RalphLoopConcerns::Scheduling

    SCHEDULING_MODES = %w[scheduled continuous one_time].freeze
    STATUSES = %w[active paused completed cancelled].freeze

    # Associations
    belongs_to :account
    belongs_to :conversation, class_name: "Ai::Conversation", foreign_key: "conversation_id"
    belongs_to :user

    # Validations
    validates :scheduling_mode, presence: true, inclusion: { in: SCHEDULING_MODES }
    validates :message_template, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :execution_count, numericality: { greater_than_or_equal_to: 0 }
    validates :max_executions, numericality: { greater_than_or_equal_to: 1 }, allow_nil: true
    validate :validate_schedule_config, if: -> { scheduling_mode != "one_time" }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :due, -> { where(status: "active").where("next_scheduled_at <= ?", Time.current) }
    scope :for_conversation, ->(conversation) { where(conversation_id: conversation.id) }

    # Callbacks
    before_create :set_initial_next_scheduled_at

    # Execute the scheduled message
    def execute!
      return unless can_execute?

      increment!(:execution_count)
      update!(last_executed_at: Time.current)

      if max_executions.present? && execution_count >= max_executions
        update!(status: "completed")
      elsif scheduling_mode != "one_time"
        schedule_next_iteration!
      else
        update!(status: "completed")
      end
    end

    def can_execute?
      status == "active" && !schedule_paused? && !exceeded_daily_limit?
    end

    def rendered_message(variables = {})
      merged = (template_variables || {}).merge(variables.stringify_keys)
      result = message_template.dup
      merged.each { |key, value| result.gsub!("{{#{key}}}", value.to_s) }
      result
    end

    private

    def set_initial_next_scheduled_at
      self.next_scheduled_at ||= calculate_next_scheduled_at
    end
  end
end
