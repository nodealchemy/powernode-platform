# frozen_string_literal: true

module Ai
  class TeamMessage < ApplicationRecord
    self.table_name = "ai_team_messages"

    MESSAGE_TYPES = %w[task_assignment task_update task_result work_plan synthesis question answer escalation coordination broadcast human_input].freeze
    PRIORITIES = %w[low normal high urgent].freeze

    # Associations
    belongs_to :team_execution, class_name: "Ai::TeamExecution", foreign_key: "team_execution_id"
    belongs_to :channel, class_name: "Ai::TeamChannel", foreign_key: "channel_id", optional: true
    belongs_to :from_role, class_name: "Ai::TeamRole", foreign_key: "from_role_id", optional: true
    belongs_to :to_role, class_name: "Ai::TeamRole", foreign_key: "to_role_id", optional: true
    belongs_to :in_reply_to, class_name: "Ai::TeamMessage", foreign_key: "in_reply_to_id", optional: true

    has_many :replies, class_name: "Ai::TeamMessage", foreign_key: :in_reply_to_id, dependent: :nullify

    # Delegate account access
    delegate :account, :agent_team, to: :team_execution

    # Validations
    validates :content, presence: true
    validates :message_type, inclusion: { in: MESSAGE_TYPES }
    validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true

    # Scopes
    scope :broadcasts, -> { where(message_type: "broadcast") }
    scope :escalations, -> { where(message_type: "escalation") }
    scope :questions, -> { where(message_type: "question") }
    scope :answers, -> { where(message_type: "answer") }
    scope :requiring_response, -> { where(requires_response: true, responded_at: nil) }
    scope :unread, -> { where(read_at: nil) }
    scope :high_priority, -> { where(priority: %w[high urgent]) }
    scope :recent, -> { order(created_at: :desc) }
    scope :ordered, -> { order(:sequence_number) }

    # Callbacks
    before_create :set_sequence_number
    after_create :record_message_on_execution

    # Message type checks
    def task_assignment?
      message_type == "task_assignment"
    end

    def task_update?
      message_type == "task_update"
    end

    def task_result?
      message_type == "task_result"
    end

    def question?
      message_type == "question"
    end

    def answer?
      message_type == "answer"
    end

    def escalation?
      message_type == "escalation"
    end

    def coordination?
      message_type == "coordination"
    end

    def broadcast?
      message_type == "broadcast"
    end

    def human_input?
      message_type == "human_input"
    end

    # Read/Response tracking
    def mark_read!
      update!(read_at: Time.current) unless read_at.present?
    end

    def mark_responded!
      update!(responded_at: Time.current) unless responded_at.present?
    end

    def read?
      read_at.present?
    end

    def responded?
      responded_at.present?
    end

    def pending_response?
      requires_response && !responded?
    end

    # Reply management
    def reply!(from:, content:, message_type: "answer")
      team_execution.messages.create!(
        channel: channel,
        from_role: from,
        to_role: from_role,
        in_reply_to: self,
        content: content,
        message_type: message_type
      ).tap do
        mark_responded!
      end
    end

    # Priority checks
    def urgent?
      priority == "urgent"
    end

    def high_priority?
      %w[high urgent].include?(priority)
    end

    private

    def set_sequence_number
      max_seq = team_execution.messages.maximum(:sequence_number) || 0
      self.sequence_number = max_seq + 1
    end

    def record_message_on_execution
      team_execution.record_message!
    end
  end
end
