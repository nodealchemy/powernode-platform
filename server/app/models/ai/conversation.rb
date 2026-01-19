# frozen_string_literal: true

module Ai
  class Conversation < ApplicationRecord
    # Authentication
    # Belongs to account - access controlled through account ownership

    # Concerns
    include Auditable

    # Associations
    belongs_to :account
    belongs_to :user
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true
    belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"
    has_many :messages, class_name: "Ai::Message", foreign_key: "ai_conversation_id", dependent: :destroy

    # Validations
    validates :conversation_id, presence: true, uniqueness: true
    validates :status, inclusion: { in: %w[active paused completed archived] }
    validates :message_count, numericality: { greater_than_or_equal_to: 0 }
    validates :total_tokens, numericality: { greater_than_or_equal_to: 0 }
    validates :total_cost, numericality: { greater_than_or_equal_to: 0 }
    validates :websocket_channel, format: { with: /\A[a-z0-9_\-]+\z/ }, allow_blank: true

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :completed, -> { where(status: "completed") }
    scope :archived, -> { where(status: "archived") }
    scope :collaborative, -> { where(is_collaborative: true) }
    scope :recent, -> { order(last_activity_at: :desc) }
    scope :for_user, ->(user) { where(user: user) }
    scope :with_agent, ->(agent) { where(ai_agent_id: agent.is_a?(Ai::Agent) ? agent.id : agent) }
    scope :active_sessions, -> { where.not(websocket_session_id: nil) }

    # Callbacks
    before_create :set_conversation_id
    before_create :set_websocket_channel
    after_update :broadcast_status_change, if: :saved_change_to_status?

    # Methods
    def active?
      status == "active"
    end

    def can_send_message?
      %w[active paused].include?(status)
    end

    def add_message(role, content, user: nil, **options)
      raise ArgumentError, "Cannot add message to inactive conversation" unless can_send_message?

      message = messages.build(
        user: user,
        message_id: UUID7.generate,
        role: role,
        content: content,
        sequence_number: next_sequence_number,
        **options
      )

      if message.save
        increment_message_count!
        update_activity_timestamp!
        broadcast_message(message)
        message
      else
        raise ActiveRecord::RecordInvalid, message
      end
    end

    def add_user_message(content, user:, **options)
      add_message("user", content, user: user, **options)
    end

    def add_assistant_message(content, **options)
      add_message("assistant", content, **options)
    end

    def add_system_message(content, **options)
      add_message("system", content, **options)
    end

    def pause_conversation!
      update!(status: "paused")
    end

    def resume_conversation!
      update!(status: "active")
    end

    def complete_conversation!(summary = nil)
      update!(
        status: "completed",
        summary: summary || generate_summary
      )
    end

    def archive_conversation!
      update!(status: "archived")
    end

    def add_participant(user)
      return false unless is_collaborative?
      return false if participants.include?(user.id)

      new_participants = participants + [user.id]
      update!(participants: new_participants)
    end

    def remove_participant(user)
      return false unless is_collaborative?

      new_participants = participants - [user.id]
      update!(participants: new_participants)
    end

    def participant_users
      return [] unless is_collaborative?

      User.where(id: participants)
    end

    def can_access?(user)
      return true if self.user == user
      return true if is_collaborative? && participants.include?(user.id)
      return true if user.has_permission?("ai.conversations.manage")

      false
    end

    def websocket_connected!(session_id)
      update!(
        websocket_session_id: session_id,
        last_activity_at: Time.current
      )
    end

    def websocket_disconnected!
      update!(
        websocket_session_id: nil
      )
    end

    def broadcast_message(message)
      return unless websocket_channel.present?

      ActionCable.server.broadcast(
        websocket_channel,
        {
          type: "message",
          conversation_id: conversation_id,
          message: message_data(message)
        }
      )
    end

    def broadcast_typing_indicator(user, typing: true)
      return unless websocket_channel.present?

      ActionCable.server.broadcast(
        websocket_channel,
        {
          type: "typing",
          conversation_id: conversation_id,
          user_id: user.id,
          typing: typing
        }
      )
    end

    def conversation_summary
      {
        id: conversation_id,
        title: title || "Conversation with #{provider.name}",
        status: status,
        message_count: message_count,
        total_tokens: total_tokens,
        total_cost: total_cost,
        agent: agent&.name,
        provider: provider.name,
        is_collaborative: is_collaborative?,
        participant_count: participants.size,
        created_at: created_at,
        last_activity_at: last_activity_at
      }
    end

    def to_param
      conversation_id
    end

    private

    def set_conversation_id
      self.conversation_id ||= SecureRandom.uuid
    end

    def set_websocket_channel
      self.websocket_channel ||= "ai_conversation_#{conversation_id}"
    end

    def next_sequence_number
      (messages.maximum(:sequence_number) || 0) + 1
    end

    def increment_message_count!
      increment!(:message_count)
    end

    def update_activity_timestamp!
      update_column(:last_activity_at, Time.current)
    end

    def broadcast_status_change
      return unless websocket_channel.present?

      ActionCable.server.broadcast(
        websocket_channel,
        {
          type: "status_change",
          conversation_id: conversation_id,
          status: status
        }
      )
    end

    def message_data(message)
      {
        id: message.message_id,
        role: message.role,
        content: message.content,
        user: message.user&.full_name,
        sequence_number: message.sequence_number,
        created_at: message.created_at,
        token_count: message.token_count
      }
    end

    def generate_summary
      return nil if message_count.zero?

      # This could be enhanced with AI-generated summaries
      "Conversation with #{message_count} messages using #{provider.name}"
    end
  end
end
