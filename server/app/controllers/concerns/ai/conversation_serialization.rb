# frozen_string_literal: true

module Ai
  module ConversationSerialization
    extend ActiveSupport::Concern

    private

    def validate_permissions
      case action_name
      when "index", "show", "stats", "messages", "active", "search", "scheduled_messages_index"
        require_permission("ai.conversations.read")
      when "create", "duplicate", "send_message", "create_team", "create_concierge", "scheduled_messages_create"
        require_permission("ai.conversations.create")
      when "update", "archive", "unarchive", "pin", "unpin", "bulk", "plan_response", "confirm_action", "scheduled_messages_update"
        require_permission("ai.conversations.update")
      when "destroy", "scheduled_messages_destroy"
        require_permission("ai.conversations.delete")
      when "worker_complete", "worker_error"
        return if current_worker || current_service
        require_permission("ai.conversations.update")
      end
    end

    def conversation_params
      params.require(:conversation).permit(:title, :status, :is_collaborative, participants: [], metadata: {})
    end

    def message_params
      params.require(:message).permit(:content, :message_type, metadata: {})
    end

    def apply_filters(conversations)
      conversations = conversations.where(status: params[:status]) if params[:status].present?
      conversations = conversations.where(ai_agent_id: params[:agent_id]) if params[:agent_id].present?
      conversations = conversations.where(user_id: params[:user_id]) if params[:user_id].present?
      conversations = conversations.pinned if params[:pinned] == "true"

      if params[:tags].present?
        tag_list = params[:tags].is_a?(Array) ? params[:tags] : params[:tags].split(",").map(&:strip)
        conversations = conversations.tagged_with_any(tag_list)
      end

      if params[:search].present?
        conversations = conversations.where("ai_conversations.title ILIKE ?", "%#{params[:search]}%")
      end

      case params[:sort_by]
      when "pinned" then conversations = conversations.reorder(nil).pinned_first
      when "last_activity" then conversations = conversations.reorder(last_activity_at: :desc)
      when "created" then conversations = conversations.reorder(created_at: :desc)
      when "message_count" then conversations = conversations.reorder(message_count: :desc)
      end

      conversations
    end

    def apply_pagination(collection)
      collection.page(params[:page]&.to_i || 1).per([ params[:per_page]&.to_i || 25, 100 ].min)
    end

    def pagination_data(collection)
      { current_page: collection.current_page, per_page: collection.limit_value, total_pages: collection.total_pages, total_count: collection.total_count }
    end

    def serialize_conversation(conversation)
      data = {
        id: conversation.id, conversation_id: conversation.conversation_id,
        title: conversation.title || "Conversation with #{conversation.provider.name}",
        status: conversation.status, message_count: conversation.message_count,
        total_tokens: conversation.total_tokens, total_cost: conversation.total_cost&.to_f,
        is_collaborative: conversation.is_collaborative?, participant_count: conversation.participants.size,
        pinned: conversation.pinned?, pinned_at: conversation.pinned_at&.iso8601, tags: conversation.tags,
        conversation_type: conversation.conversation_type,
        created_at: conversation.created_at.iso8601, last_activity_at: conversation.last_activity_at&.iso8601,
        ai_agent: conversation.agent ? { id: conversation.agent.id, name: conversation.agent.name, agent_type: conversation.agent.agent_type, is_concierge: conversation.agent.is_concierge? } : nil,
        provider: { id: conversation.provider.id, name: conversation.provider.name, provider_type: conversation.provider.provider_type },
        user: { id: conversation.user.id, name: conversation.user.full_name, email: conversation.user.email }
      }

      if conversation.team_conversation? && conversation.agent_team
        data[:agent_team] = { id: conversation.agent_team.id, name: conversation.agent_team.name }
      end

      data
    end

    def serialize_conversation_detail(conversation)
      serialize_conversation(conversation).merge(
        summary: conversation.summary, websocket_channel: conversation.websocket_channel,
        websocket_session_id: conversation.websocket_session_id,
        participants: conversation.is_collaborative? ? (conversation.participants || []) : [],
        recent_messages: conversation.messages.not_deleted.recent.limit(10).map { |m| serialize_message(m) },
        metadata: { can_send_message: conversation.can_send_message?, active_session: conversation.websocket_session_id.present? }
      )
    end

    def serialize_message(message)
      message.message_data
    end
  end
end
