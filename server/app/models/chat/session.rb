# frozen_string_literal: true

module Chat
  class Session < ApplicationRecord
    self.table_name = "chat_sessions"

    # Concerns
    include Auditable

    # Status constants
    STATUSES = %w[active idle closed blocked].freeze

    # Context window size limit
    MAX_CONTEXT_MESSAGES = 50

    # Associations
    belongs_to :channel, class_name: "Chat::Channel"
    belongs_to :ai_conversation, class_name: "Ai::Conversation", optional: true
    belongs_to :assigned_agent, class_name: "Ai::Agent", optional: true

    has_many :messages, class_name: "Chat::Message", foreign_key: "session_id", dependent: :destroy
    has_many :a2a_tasks, class_name: "Ai::A2aTask", foreign_key: "chat_session_id"

    # Delegations
    delegate :account, to: :channel
    delegate :platform, to: :channel

    # Validations
    validates :platform_user_id, presence: true
    validates :platform_user_id, uniqueness: { scope: :channel_id }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :message_count, numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :idle, -> { where(status: "idle") }
    scope :closed, -> { where(status: "closed") }
    scope :blocked, -> { where(status: "blocked") }
    scope :open, -> { where(status: %w[active idle]) }
    scope :for_user, ->(platform_user_id) { where(platform_user_id: platform_user_id) }
    scope :recently_active, -> { where("last_activity_at > ?", 1.hour.ago) }
    scope :stale, -> { where("last_activity_at < ?", 24.hours.ago).where(status: %w[active idle]) }

    # Callbacks
    after_create :create_ai_conversation
    after_update :handle_status_change, if: :saved_change_to_status?

    # Status methods
    def active?
      status == "active"
    end

    def idle?
      status == "idle"
    end

    def closed?
      status == "closed"
    end

    def blocked?
      status == "blocked"
    end

    def can_receive_messages?
      %w[active idle].include?(status) && !channel.user_blacklisted?(platform_user_id)
    end

    # Status transitions
    def activate!
      update!(status: "active")
    end

    def mark_idle!
      update!(status: "idle") if active?
    end

    def close!(reason: nil)
      update!(
        status: "closed",
        closed_at: Time.current,
        user_metadata: user_metadata.merge("close_reason" => reason)
      )
    end

    def block!(reason: nil)
      update!(
        status: "blocked",
        user_metadata: user_metadata.merge("block_reason" => reason)
      )
    end

    def reopen!
      return false if blocked?

      update!(status: "active", closed_at: nil)
    end

    # Activity tracking
    def touch_activity!
      update_column(:last_activity_at, Time.current)
      activate! if idle?
    end

    # Message handling
    def add_inbound_message(content:, message_type: "text", platform_message_id: nil, metadata: {})
      sanitized = sanitize_content(content)

      message = messages.create!(
        direction: "inbound",
        message_type: message_type,
        content: content,
        sanitized_content: sanitized,
        platform_message_id: platform_message_id,
        platform_metadata: metadata,
        delivery_status: "delivered",
        delivered_at: Time.current
      )

      increment!(:message_count)
      touch_activity!
      update_context_window(message)
      channel.record_message!

      message
    end

    def add_outbound_message(content:, message_type: "text", ai_message: nil)
      message = messages.create!(
        direction: "outbound",
        message_type: message_type,
        content: content,
        sanitized_content: content,
        ai_message: ai_message,
        delivery_status: "pending",
        sent_at: Time.current
      )

      increment!(:message_count)
      touch_activity!
      update_context_window(message)

      message
    end

    # Agent management
    def transfer_to_agent!(new_agent)
      old_agent = assigned_agent

      update!(assigned_agent: new_agent)
      increment!(:agent_handoff_count)

      # Log the transfer
      add_system_note("Agent transfer: #{old_agent&.name || 'None'} → #{new_agent.name}")

      new_agent
    end

    def escalate_to_human!
      update!(
        user_metadata: user_metadata.merge(
          "escalated_at" => Time.current.iso8601,
          "needs_human" => true
        )
      )
    end

    # Context window for AI
    def context_for_agent
      {
        session_id: id,
        platform: platform,
        platform_user_id: platform_user_id,
        platform_username: platform_username,
        message_history: context_window["messages"] || [],
        user_metadata: user_metadata,
        message_count: message_count,
        session_started_at: created_at.iso8601
      }
    end

    # Summary for API
    def session_summary
      {
        id: id,
        platform_user_id: platform_user_id,
        platform_username: platform_username,
        status: status,
        message_count: message_count,
        assigned_agent: assigned_agent&.name,
        last_activity_at: last_activity_at,
        created_at: created_at
      }
    end

    def session_details
      session_summary.merge(
        channel_id: channel_id,
        channel_name: channel.name,
        platform: platform,
        ai_conversation_id: ai_conversation_id,
        agent_handoff_count: agent_handoff_count,
        user_metadata: user_metadata,
        context_messages: (context_window["messages"] || []).size,
        closed_at: closed_at
      )
    end

    private

    def create_ai_conversation
      return if ai_conversation.present?

      # Create linked AI conversation for this chat session
      conversation = Ai::Conversation.create!(
        account: account,
        user: account.owner,  # Default to account owner
        ai_provider_id: assigned_agent&.ai_provider_id || Ai::Provider.default_for_account(account)&.id,
        ai_agent_id: assigned_agent_id,
        title: "Chat: #{platform} - #{platform_username || platform_user_id}",
        status: "active",
        metadata: { chat_session_id: id, platform: platform }
      )

      update!(ai_conversation: conversation)
    rescue StandardError => e
      Rails.logger.error "Failed to create AI conversation for chat session: #{e.message}"
    end

    def handle_status_change
      case status
      when "closed"
        ai_conversation&.complete_conversation!
      when "blocked"
        ai_conversation&.pause_conversation!
      when "active"
        ai_conversation&.resume_conversation! if ai_conversation&.status == "paused"
      end
    end

    def sanitize_content(content)
      return content if content.blank?

      # Wrap in safe delimiters to prevent prompt injection
      sanitized = content.to_s.strip

      # Remove potentially dangerous patterns
      sanitized = sanitized.gsub(/\[USER_MESSAGE_START\]|\[USER_MESSAGE_END\]/, "")
      sanitized = sanitized.gsub(/\[SYSTEM\]|\[INSTRUCTION\]|\[IGNORE\]/, "")

      # Wrap in safe delimiters
      "[USER_MESSAGE_START]\n#{sanitized}\n[USER_MESSAGE_END]"
    end

    def update_context_window(message)
      current_messages = context_window["messages"] || []

      # Add new message to context
      current_messages << {
        "role" => message.direction == "inbound" ? "user" : "assistant",
        "content" => message.sanitized_content || message.content,
        "timestamp" => message.created_at.iso8601
      }

      # Keep only recent messages
      if current_messages.size > MAX_CONTEXT_MESSAGES
        current_messages = current_messages.last(MAX_CONTEXT_MESSAGES)
      end

      update_column(:context_window, { "messages" => current_messages, "updated_at" => Time.current.iso8601 })
    end

    def add_system_note(note)
      messages.create!(
        direction: "outbound",
        message_type: "text",
        content: "[SYSTEM] #{note}",
        sanitized_content: "[SYSTEM] #{note}",
        delivery_status: "delivered",
        platform_metadata: { system_note: true }
      )
    end
  end
end
