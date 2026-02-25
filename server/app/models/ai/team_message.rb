# frozen_string_literal: true

module Ai
  class TeamMessage < ApplicationRecord
    self.table_name = "ai_team_messages"

    MESSAGE_TYPES = %w[task_assignment task_update task_result work_plan synthesis question answer escalation coordination broadcast human_input].freeze
    PRIORITIES = %w[low normal high urgent].freeze

    # Associations
    belongs_to :team_execution, class_name: "Ai::TeamExecution", foreign_key: "team_execution_id", optional: true
    belongs_to :channel, class_name: "Ai::TeamChannel", foreign_key: "channel_id", optional: true
    belongs_to :from_role, class_name: "Ai::TeamRole", foreign_key: "from_role_id", optional: true
    belongs_to :to_role, class_name: "Ai::TeamRole", foreign_key: "to_role_id", optional: true
    belongs_to :in_reply_to, class_name: "Ai::TeamMessage", foreign_key: "in_reply_to_id", optional: true
    belongs_to :user, optional: true

    has_many :replies, class_name: "Ai::TeamMessage", foreign_key: :in_reply_to_id, dependent: :nullify

    # Delegate account access — fall back to channel's team when no execution
    def account
      team_execution&.account || channel&.account
    end

    def agent_team
      team_execution&.agent_team || channel&.agent_team
    end

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
    after_create_commit :broadcast_to_channel_subscribers
    after_create_commit :sync_to_bridged_platforms

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

    def work_plan?
      message_type == "work_plan"
    end

    def synthesis?
      message_type == "synthesis"
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
      scope = if team_execution.present?
                team_execution.messages
              elsif channel.present?
                channel.messages
              else
                self.class.none
              end
      max_seq = scope.maximum(:sequence_number) || 0
      self.sequence_number = max_seq + 1
    end

    def record_message_on_execution
      team_execution&.record_message!
    end

    def broadcast_to_channel_subscribers
      return unless channel.present?

      ActionCable.server.broadcast(
        "team_channel:#{channel.id}",
        {
          type: "message_created",
          message: self.class.serialize_for_broadcast(self),
          channel_id: channel.id
        }
      )
    end

    def sync_to_bridged_platforms
      return unless channel.present?
      return unless channel.chat_channels.where(bridge_enabled: true).exists?
      return if metadata&.dig("source") == "chat_bridge"

      Ai::TeamChannelBridgeService.new.sync_outbound_to_platform(self)
    end

    class << self
      def serialize_for_broadcast(msg)
        {
          id: msg.id,
          content: msg.content,
          message_type: msg.message_type,
          priority: msg.priority,
          from_role: msg.from_role ? { id: msg.from_role.id, role_name: msg.from_role.role_name, agent_name: msg.from_role.ai_agent&.name } : nil,
          to_role: msg.to_role ? { id: msg.to_role.id, role_name: msg.to_role.role_name, agent_name: msg.to_role.ai_agent&.name } : nil,
          user: msg.user ? { id: msg.user.id, name: msg.user.name, email: msg.user.email } : nil,
          requires_response: msg.requires_response,
          responded_at: msg.responded_at,
          sequence_number: msg.sequence_number,
          created_at: msg.created_at
        }
      end
    end
  end
end
