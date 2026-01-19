# frozen_string_literal: true

module Ai
  class TeamChannel < ApplicationRecord
    self.table_name = "ai_team_channels"

    CHANNEL_TYPES = %w[broadcast direct topic task escalation].freeze

    # Associations
    belongs_to :agent_team, class_name: "AiAgentTeam"

    has_many :messages, class_name: "Ai::TeamMessage", foreign_key: :channel_id, dependent: :destroy

    # Delegate account access
    delegate :account, to: :agent_team

    # Validations
    validates :name, presence: true
    validates :name, uniqueness: { scope: :agent_team_id }
    validates :channel_type, presence: true, inclusion: { in: CHANNEL_TYPES }

    # Scopes
    scope :broadcast, -> { where(channel_type: "broadcast") }
    scope :direct, -> { where(channel_type: "direct") }
    scope :topic_channels, -> { where(channel_type: "topic") }
    scope :task_channels, -> { where(channel_type: "task") }
    scope :escalation, -> { where(channel_type: "escalation") }
    scope :persistent, -> { where(is_persistent: true) }

    # Channel type checks
    def broadcast?
      channel_type == "broadcast"
    end

    def direct?
      channel_type == "direct"
    end

    def topic?
      channel_type == "topic"
    end

    def task_channel?
      channel_type == "task"
    end

    def escalation?
      channel_type == "escalation"
    end

    # Participant management
    def add_participant(role_id)
      return if participant_roles.include?(role_id)

      update!(participant_roles: participant_roles + [role_id])
    end

    def remove_participant(role_id)
      update!(participant_roles: participant_roles - [role_id])
    end

    def has_participant?(role_id)
      participant_roles.include?(role_id) || broadcast?
    end

    # Message retention
    def cleanup_old_messages!
      return unless message_retention_hours.present?

      cutoff = message_retention_hours.hours.ago
      messages.where("created_at < ?", cutoff).destroy_all
    end

    # Message count
    def message_count
      messages.count
    end

    def recent_messages(limit = 10)
      messages.order(created_at: :desc).limit(limit)
    end
  end
end
