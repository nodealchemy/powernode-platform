# frozen_string_literal: true

module Ai
  module Tools
    class ConciergeTool < BaseTool
      REQUIRED_PERMISSION = "ai.conversations.create"

      def self.definition
        {
          name: "concierge",
          description: "Interact with the Powernode concierge: send messages, confirm actions, list conversations, and retrieve message history",
          parameters: {
            action: { type: "string", required: true, description: "Action: send_concierge_message, confirm_concierge_action, list_conversations, get_conversation_messages" },
            message: { type: "string", required: false, description: "Message to send to the concierge (for send_concierge_message)" },
            conversation_id: { type: "string", required: false, description: "Conversation ID (for confirm_concierge_action, get_conversation_messages)" },
            action_type: { type: "string", required: false, description: "Action type to confirm: create_mission, delegate_to_team, code_review, deploy (for confirm_concierge_action)" },
            action_params: { type: "object", required: false, description: "Parameters for the confirmed action (for confirm_concierge_action)" },
            status: { type: "string", required: false, description: "Filter by conversation status (for list_conversations)" },
            limit: { type: "integer", required: false, description: "Max results (default 10)" }
          }
        }
      end

      def self.action_definitions
        {
          "send_concierge_message" => {
            description: "Send a message to the Powernode concierge and get an AI response. Creates or reuses an active concierge conversation for the current user.",
            parameters: {
              message: { type: "string", required: true, description: "Message to send to the concierge" }
            }
          },
          "confirm_concierge_action" => {
            description: "Confirm a pending concierge action (create_mission, delegate_to_team, code_review, deploy). Resolves the pending action and executes it.",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Conversation ID containing the pending action" },
              action_type: { type: "string", required: true, description: "Action type to confirm: create_mission, delegate_to_team, code_review, deploy" },
              action_params: { type: "object", required: false, description: "Optional parameters to pass to the action (overrides original params)" }
            }
          },
          "list_conversations" => {
            description: "List the current user's recent conversations with agent name, message count, and last activity",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status: active, paused, completed, archived (default: all)" },
              limit: { type: "integer", required: false, description: "Max results (default 10, max 50)" }
            }
          },
          "get_conversation_messages" => {
            description: "Retrieve message history for a conversation including role, content, metadata, and timestamps",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Conversation ID to retrieve messages from" },
              limit: { type: "integer", required: false, description: "Max messages to return (default 20, max 100)" }
            }
          }
        }
      end

      protected

      def call(params)
        return { success: false, error: "User context required for concierge tools" } unless user

        case params[:action]
        when "send_concierge_message" then send_concierge_message(params)
        when "confirm_concierge_action" then confirm_concierge_action(params)
        when "list_conversations" then list_conversations(params)
        when "get_conversation_messages" then get_conversation_messages(params)
        else
          { success: false, error: "Unknown action: #{params[:action]}. Valid: send_concierge_message, confirm_concierge_action, list_conversations, get_conversation_messages" }
        end
      end

      private

      def send_concierge_message(params)
        return { success: false, error: "message is required" } if params[:message].blank?

        concierge_agent = account.ai_agents.default_concierge.first
        return { success: false, error: "No concierge agent configured for this account" } unless concierge_agent

        conversation = find_or_create_concierge_conversation(concierge_agent)

        # Add the user message to the conversation
        conversation.add_user_message(params[:message], user: user)

        # Process via ConciergeService
        service = Ai::ConciergeService.new(conversation: conversation, user: user)
        service.process_message(params[:message])

        # Retrieve the assistant's response (last assistant message)
        last_message = conversation.messages.not_deleted.where(role: "assistant").order(created_at: :desc).first

        # Notify user if they're not connected to this conversation's WebSocket
        notify_user_of_response(conversation, concierge_agent, last_message) if last_message

        response = {
          success: true,
          conversation_id: conversation.conversation_id,
          response: last_message&.content,
          message_id: last_message&.message_id
        }

        # Check for pending action in the response metadata
        if last_message&.content_metadata&.dig("concierge_action")
          response[:pending_action] = {
            action_type: last_message.content_metadata.dig("action_context", "action_type"),
            status: last_message.content_metadata.dig("action_context", "status"),
            actions: last_message.content_metadata["actions"]
          }
        end

        response
      rescue StandardError => e
        Rails.logger.error("[ConciergeTool] send_concierge_message error: #{e.message}")
        { success: false, error: "Failed to process message: #{e.message}" }
      end

      def confirm_concierge_action(params)
        return { success: false, error: "conversation_id is required" } if params[:conversation_id].blank?
        return { success: false, error: "action_type is required" } if params[:action_type].blank?

        conversation = find_conversation(params[:conversation_id])
        return { success: false, error: "Conversation not found" } unless conversation
        return { success: false, error: "Not a concierge conversation" } unless conversation.agent&.is_concierge?

        action_params = params[:action_params] || {}
        action_params = action_params.to_h if action_params.respond_to?(:to_h)

        # Fall back to the pending action's original params if none provided
        if action_params.empty?
          pending = find_pending_action(conversation, params[:action_type])
          action_params = pending&.dig("action_params") || {}
        end

        service = Ai::ConciergeService.new(conversation: conversation, user: user)
        service.handle_confirmed_action(params[:action_type], action_params)

        last_message = conversation.messages.not_deleted.order(created_at: :desc).first

        {
          success: true,
          conversation_id: conversation.conversation_id,
          action_type: params[:action_type],
          result: last_message&.content
        }
      rescue StandardError => e
        Rails.logger.error("[ConciergeTool] confirm_concierge_action error: #{e.message}")
        { success: false, error: "Failed to confirm action: #{e.message}" }
      end

      def list_conversations(params)
        scope = Ai::Conversation.where(account: account, user: user)
        scope = scope.where(status: params[:status]) if params[:status].present?

        limit = (params[:limit] || 10).to_i.clamp(1, 50)
        conversations = scope.includes(:agent, :provider).order(last_activity_at: :desc).limit(limit)

        {
          success: true,
          count: conversations.size,
          conversations: conversations.map { |c| serialize_conversation(c) }
        }
      end

      def get_conversation_messages(params)
        return { success: false, error: "conversation_id is required" } if params[:conversation_id].blank?

        conversation = find_conversation(params[:conversation_id])
        return { success: false, error: "Conversation not found" } unless conversation

        limit = (params[:limit] || 20).to_i.clamp(1, 100)
        messages = conversation.messages.not_deleted.ordered.last(limit)

        {
          success: true,
          conversation_id: conversation.conversation_id,
          agent: conversation.agent&.name,
          count: messages.size,
          messages: messages.map { |m| serialize_message(m) }
        }
      end

      # --- Helpers ---

      def find_or_create_concierge_conversation(concierge_agent)
        # Reuse existing active conversation
        existing = concierge_agent.conversations.active
          .where(user_id: user.id)
          .order(last_activity_at: :desc).first

        return existing if existing

        # Create new conversation (mirrors conversations_controller#create_concierge)
        concierge_agent.conversations.create!(
          conversation_id: SecureRandom.uuid,
          user_id: user.id,
          account_id: account.id,
          ai_provider_id: concierge_agent.ai_provider_id,
          title: "Chat with #{concierge_agent.name}",
          status: "active",
          conversation_type: "agent",
          last_activity_at: Time.current
        )
      end

      def find_conversation(conversation_id)
        Ai::Conversation.where(account: account, user: user)
          .find_by(id: conversation_id) ||
          Ai::Conversation.where(account: account, user: user)
            .find_by(conversation_id: conversation_id)
      end

      def find_pending_action(conversation, action_type)
        message = conversation.messages
          .where(role: "assistant")
          .order(created_at: :desc)
          .find { |m|
            m.content_metadata&.dig("concierge_action") &&
              m.content_metadata&.dig("action_context", "status") == "pending" &&
              m.content_metadata&.dig("action_context", "action_type") == action_type
          }

        message&.content_metadata
      end

      def serialize_conversation(conversation)
        {
          id: conversation.id,
          conversation_id: conversation.conversation_id,
          title: conversation.title,
          status: conversation.status,
          agent: conversation.agent&.name,
          provider: conversation.provider&.name,
          message_count: conversation.message_count,
          is_concierge: conversation.agent&.is_concierge?,
          pinned: conversation.pinned?,
          tags: conversation.tags,
          last_activity_at: conversation.last_activity_at&.iso8601,
          created_at: conversation.created_at&.iso8601
        }
      end

      def notify_user_of_response(conversation, concierge_agent, last_message)
        # Skip if user is actively viewing this conversation via WebSocket
        return if conversation.websocket_session_id.present?

        # Throttle: skip if a concierge notification was created for this conversation in the last 60 seconds
        recent = Notification.where(
          user: user,
          notification_type: "ai_concierge_message"
        ).where("created_at > ?", 60.seconds.ago).find do |n|
          n.metadata&.dig("conversation_id") == conversation.conversation_id
        end
        return if recent

        Notification.create_for_user(
          user,
          type: "ai_concierge_message",
          title: "Message from #{concierge_agent.name}",
          message: last_message.content.to_s.truncate(120),
          severity: "info",
          category: "ai",
          action_url: "/app/ai/chat",
          action_label: "Open Chat",
          metadata: {
            conversation_id: conversation.conversation_id,
            agent_id: concierge_agent.id,
            message_id: last_message.message_id
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[ConciergeTool] Failed to create notification: #{e.message}")
      end

      def serialize_message(message)
        {
          id: message.message_id,
          role: message.role,
          content: message.content.to_s.truncate(2000),
          status: message.status,
          is_edited: message.is_edited?,
          content_metadata: message.content_metadata.presence,
          created_at: message.created_at&.iso8601
        }
      end
    end
  end
end
