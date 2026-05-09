# frozen_string_literal: true

# AiConversationsListChannel - List-level CRUD events for the chat sidebar.
#
# Distinct from AiConversationChannel (which broadcasts message-level events
# inside a single conversation). This channel publishes account-scoped
# created/updated/destroyed events so the sidebar reflects new conversations
# from other tabs/devices and removes deleted ones without HTTP refetch.
#
# Subscription:
#   channel.subscribe()  # auto-scoped to current_user.account_id
class AiConversationsListChannel < ApplicationCable::Channel
  def subscribed
    unless current_user&.account_id
      reject
      return
    end

    stream_from self.class.stream_name(current_user.account_id)
    transmit(type: "subscription.confirmed", timestamp: Time.current.iso8601)
  end

  def unsubscribed
    stop_all_streams
  end

  class << self
    def stream_name(account_id)
      "ai_conversations_list:account_#{account_id}"
    end

    def broadcast_created(conversation)
      broadcast_event(conversation, "conversation_created")
    end

    def broadcast_updated(conversation)
      broadcast_event(conversation, "conversation_updated")
    end

    def broadcast_destroyed(conversation)
      ActionCable.server.broadcast(
        stream_name(conversation.account_id),
        {
          type: "conversation_destroyed",
          conversation_id: conversation.id,
          timestamp: Time.current.iso8601
        }
      )
    end

    private

    def broadcast_event(conversation, type)
      ActionCable.server.broadcast(
        stream_name(conversation.account_id),
        {
          type: type,
          conversation: serialize(conversation),
          timestamp: Time.current.iso8601
        }
      )
    end

    def serialize(c)
      {
        id: c.id,
        conversation_id: c.conversation_id,
        account_id: c.account_id,
        ai_agent_id: c.ai_agent_id,
        title: c.title,
        status: c.status,
        message_count: c.message_count,
        conversation_type: c.conversation_type,
        pinned: c.pinned?,
        pinned_at: c.pinned_at&.iso8601,
        tags: c.tags,
        created_at: c.created_at.iso8601,
        last_activity_at: c.last_activity_at&.iso8601,
        ai_agent: c.agent && { id: c.agent.id, name: c.agent.name, agent_type: c.agent.agent_type, is_concierge: c.agent.is_concierge? },
        agent_team: (c.team_conversation? && c.agent_team) ? { id: c.agent_team.id, name: c.agent_team.name, team_type: c.agent_team.team_type } : nil
      }
    end
  end
end
