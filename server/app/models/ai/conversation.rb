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
    belongs_to :agent_team, class_name: "Ai::AgentTeam", foreign_key: "agent_team_id", optional: true
    has_many :messages, class_name: "Ai::Message", foreign_key: "ai_conversation_id", dependent: :destroy
    has_many :scheduled_messages, class_name: "Ai::ScheduledMessage", foreign_key: "conversation_id", dependent: :destroy
    has_one :mission, class_name: "Ai::Mission", foreign_key: "conversation_id", dependent: :nullify
    has_many :team_executions, class_name: "Ai::TeamExecution", foreign_key: "ai_conversation_id", dependent: :nullify
    has_many :chat_sessions, class_name: "Chat::Session", foreign_key: "ai_conversation_id", dependent: :nullify

    # Validations
    validates :conversation_id, presence: true, uniqueness: true
    validates :status, inclusion: { in: %w[active paused completed archived] }
    validates :conversation_type, inclusion: { in: %w[agent team] }
    validates :message_count, numericality: { greater_than_or_equal_to: 0 }
    validates :total_tokens, numericality: { greater_than_or_equal_to: 0 }
    validates :total_cost, numericality: { greater_than_or_equal_to: 0 }
    validates :websocket_channel, format: { with: /\A[a-z0-9_\-]+\z/ }, allow_blank: true
    validate :team_conversation_requires_team

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :completed, -> { where(status: "completed") }
    scope :archived, -> { where(status: "archived") }
    scope :team_conversations, -> { where(conversation_type: "team") }
    scope :for_team, ->(team) { where(agent_team_id: team.is_a?(Ai::AgentTeam) ? team.id : team) }
    scope :collaborative, -> { where(is_collaborative: true) }
    scope :recent, -> { order(last_activity_at: :desc) }
    scope :for_user, ->(user) { where(user: user) }
    scope :with_agent, ->(agent) { where(ai_agent_id: agent.is_a?(Ai::Agent) ? agent.id : agent) }
    scope :active_sessions, -> { where.not(websocket_session_id: nil) }
    scope :pinned, -> { where.not(pinned_at: nil).order(pinned_at: :desc) }
    scope :unpinned, -> { where(pinned_at: nil) }
    scope :tagged_with, ->(tag) { where("tags @> ?", [tag].to_json) }
    scope :tagged_with_any, ->(tags) { where("tags ?| array[:tags]", tags: tags) }
    scope :by_last_activity, -> { order(last_activity_at: :desc) }
    scope :pinned_first, -> { order(Arel.sql("CASE WHEN pinned_at IS NOT NULL THEN 0 ELSE 1 END, pinned_at DESC, last_activity_at DESC")) }

    # Callbacks
    before_validation :set_conversation_id, on: :create
    before_validation :set_websocket_channel, on: :create
    after_update :broadcast_status_change, if: :saved_change_to_status?

    # Methods
    def active?
      status == "active"
    end

    def team_conversation?
      conversation_type == "team"
    end

    def workspace_conversation?
      agent_team&.team_type == "workspace"
    end

    def can_send_message?
      %w[active paused].include?(status)
    end

    def add_message(role, content, user: nil, agent: nil, **options)
      raise ArgumentError, "Cannot add message to inactive conversation" unless can_send_message?

      message = messages.build(
        user: user,
        ai_agent_id: (agent || self.agent)&.id,
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

    def pin!
      update!(pinned_at: Time.current)
    end

    def unpin!
      update!(pinned_at: nil)
    end

    def pinned?
      pinned_at.present?
    end

    def add_tag(tag)
      tag = tag.to_s.strip.downcase
      return if tags.include?(tag)

      update!(tags: tags + [tag])
    end

    def remove_tag(tag)
      tag = tag.to_s.strip.downcase
      update!(tags: tags - [tag])
    end

    def add_participant(user)
      return false unless is_collaborative?
      return false if participants.include?(user.id)

      new_participants = participants + [ user.id ]
      update!(participants: new_participants)
    end

    def remove_participant(user)
      return false unless is_collaborative?

      new_participants = participants - [ user.id ]
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

      AiConversationChannel.broadcast_message_created(self, message)
      notify_mcp_sessions_of_message(message)
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
        pinned: pinned?,
        tags: tags,
        created_at: created_at,
        last_activity_at: last_activity_at
      }
    end

    # Full-text search across conversation messages
    def self.search_messages(query, account_id:)
      joins(:messages)
        .where(account_id: account_id)
        .where("ai_messages.search_vector @@ plainto_tsquery('english', ?)", query)
        .where(ai_messages: { deleted_at: nil })
        .distinct
    end

    def to_param
      conversation_id
    end

    private

    def notify_mcp_sessions_of_message(message)
      return unless agent_team.present?

      # Find MCP client agents in this workspace team
      mcp_agent_ids = agent_team.members
        .joins(:agent)
        .where(ai_agents: { agent_type: "mcp_client" })
        .pluck(:ai_agent_id)

      return if mcp_agent_ids.empty?

      # Skip notifying the agent that sent this message (avoid echo)
      mcp_agent_ids -= [message.ai_agent_id] if message.ai_agent_id.present?
      return if mcp_agent_ids.empty?

      # For workspace conversations, only notify MCP clients that are either:
      #   1. The primary agent (concierge) — always receives messages
      #   2. Explicitly @mentioned in structured metadata or text content
      # This prevents non-mentioned agents from receiving every message.
      if workspace_conversation?
        mentioned_agent_ids = resolve_mentioned_mcp_agents(message, mcp_agent_ids)

        # Primary agent always receives; others only when @mentioned
        mcp_agent_ids = mcp_agent_ids.select do |agent_id|
          agent_id == ai_agent_id || mentioned_agent_ids.include?(agent_id)
        end
        return if mcp_agent_ids.empty?
      end

      sessions = McpSession.active.where(ai_agent_id: mcp_agent_ids)
      return if sessions.empty?

      notification = {
        type: "message_created",
        conversation_id: conversation_id,
        workspace: agent_team.name,
        message: {
          id: message.message_id,
          role: message.role,
          content: message.content.to_s.truncate(500),
          sender: message.user&.name || message.agent&.name || "Unknown",
          created_at: message.created_at&.iso8601
        }
      }.to_json

      sessions.find_each do |session|
        ActionCable.server.pubsub.broadcast("mcp_session:#{session.session_token}", notification)
      end
    rescue StandardError => e
      Rails.logger.warn("[Conversation] Failed to notify MCP sessions: #{e.message}")
    end

    # Resolve which MCP agents are @mentioned in a message, checking both
    # structured content_metadata and raw @Name text patterns in the content.
    def resolve_mentioned_mcp_agents(message, candidate_agent_ids)
      # 1. Structured mentions from content_metadata (frontend path)
      structured_names = Array(message.content_metadata&.dig("mentions")).filter_map { |m| m["name"] || m[:name] }
      mentioned_ids = if structured_names.present?
        agent_team.members.by_agent_names(structured_names).pluck(:ai_agent_id)
      else
        []
      end

      # 2. Text @mentions from content (agent-to-agent tool path)
      #    Only scan if structured mentions didn't already match all candidates
      if mentioned_ids.empty? || (candidate_agent_ids - mentioned_ids).any?
        content = message.content.to_s
        if content.include?("@")
          mcp_agents = Ai::Agent.where(id: candidate_agent_ids).pluck(:id, :name)
          mcp_agents.each do |agent_id, agent_name|
            next if mentioned_ids.include?(agent_id)
            mentioned_ids << agent_id if content.include?("@#{agent_name}")
          end
        end
      end

      mentioned_ids
    end

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

    def team_conversation_requires_team
      if conversation_type == "team" && agent_team_id.blank?
        errors.add(:agent_team_id, "is required for team conversations")
      end
    end
  end
end
