# frozen_string_literal: true

# AiConversationChannel - Real-time messaging for AI conversations
#
# Handles WebSocket communication for AI agent conversations including:
# - User message sending
# - AI response streaming
# - Typing indicators
#
# Subscription:
#   channel.subscribe(conversation_id: conversation_id)
#
class AiConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation_id = params[:conversation_id]

    unless conversation_id.present?
      reject
      return
    end

    # Try to find by id first, then by conversation_id field
    @conversation = ::Ai::Conversation.find_by(id: conversation_id) ||
                    ::Ai::Conversation.find_by(conversation_id: conversation_id)

    unless @conversation && authorized_for_conversation?(@conversation)
      Rails.logger.warn "[AiConversationChannel] Unauthorized or not found: conversation=#{conversation_id} user=#{current_user&.id}"
      reject
      return
    end

    # Use the conversation's websocket_channel if set, otherwise create stream name
    stream_name = @conversation.websocket_channel.presence || conversation_stream_name(@conversation.id)
    stream_from stream_name

    Rails.logger.info "[AiConversationChannel] Subscribed: user=#{current_user.id} conversation=#{conversation_id} stream=#{stream_name}"

    transmit({
      type: "subscription.confirmed",
      conversation_id: @conversation.conversation_id || @conversation.id,
      timestamp: Time.current.iso8601
    })
  end

  def unsubscribed
    Rails.logger.info "[AiConversationChannel] Unsubscribed: user=#{current_user&.id}"
    stop_all_streams
  end

  # Handle incoming user messages
  #
  # @param data [Hash] Message data with :content key
  def send_message(data)
    content = data["content"]

    unless content.present?
      transmit_error("Message content is required")
      return
    end

    unless @conversation
      transmit_error("Conversation not found")
      return
    end

    unless @conversation.can_send_message?
      transmit_error("Cannot send message to this conversation")
      return
    end

    # Create the user message using the model's method
    message = @conversation.add_user_message(content, user: current_user)

    # Broadcast the message to all subscribers (model already broadcasts via broadcast_message)
    # Also broadcast in our expected format for frontend compatibility
    broadcast_message_created(message)

    # Trigger AI response (async) - only if agent is configured
    trigger_ai_response(message) if @conversation.agent.present?

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[AiConversationChannel] Validation error: #{e.message}"
    transmit_error("Failed to save message: #{e.record.errors.full_messages.join(', ')}")
  rescue StandardError => e
    Rails.logger.error "[AiConversationChannel] Error sending message: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    transmit_error("Failed to send message")
  end

  # Handle typing indicator
  #
  # @param data [Hash] Typing data with :typing boolean
  def typing_indicator(data)
    typing = data["typing"] == true

    broadcast_to_conversation({
      type: "typing_indicator",
      user_id: current_user.id,
      user_name: current_user.name || current_user.email,
      typing: typing,
      timestamp: Time.current.iso8601
    })
  end

  # ==========================================================================
  # CLASS METHODS FOR BROADCASTING
  # ==========================================================================

  class << self
    # Broadcast a new message to conversation subscribers
    #
    # @param conversation [Ai::Conversation] The conversation
    # @param message [Ai::Message] The message to broadcast
    def broadcast_message_created(conversation, message)
      stream_name = conversation.websocket_channel.presence || conversation_stream_name(conversation.id)

      ActionCable.server.broadcast(
        stream_name,
        {
          type: "message_created",
          conversation_id: conversation.conversation_id,
          workspace: conversation.agent_team&.name,
          message: serialize_message(message),
          timestamp: Time.current.iso8601
        }
      )
    end

    # Broadcast AI response streaming update
    #
    # @param conversation [Ai::Conversation] The conversation
    # @param message [Ai::Message] The AI message being streamed
    def broadcast_ai_streaming(conversation, message)
      stream_name = conversation.websocket_channel.presence || conversation_stream_name(conversation.id)

      ActionCable.server.broadcast(
        stream_name,
        {
          type: "ai_response_streaming",
          conversation_id: conversation.conversation_id,
          message: serialize_message(message),
          timestamp: Time.current.iso8601
        }
      )
    end

    # Broadcast AI response completion
    #
    # @param conversation [Ai::Conversation] The conversation
    # @param message [Ai::Message] The completed AI message
    def broadcast_ai_complete(conversation, message)
      stream_name = conversation.websocket_channel.presence || conversation_stream_name(conversation.id)

      ActionCable.server.broadcast(
        stream_name,
        {
          type: "ai_response_complete",
          conversation_id: conversation.conversation_id,
          message: serialize_message(message),
          timestamp: Time.current.iso8601
        }
      )
    end

    # Broadcast a message update (e.g., action_context changed)
    #
    # @param conversation [Ai::Conversation] The conversation
    # @param message [Ai::Message] The updated message
    def broadcast_message_updated(conversation, message)
      stream_name = conversation.websocket_channel.presence || conversation_stream_name(conversation.id)

      ActionCable.server.broadcast(
        stream_name,
        {
          type: "message_updated",
          conversation_id: conversation.conversation_id,
          message: serialize_message(message),
          timestamp: Time.current.iso8601
        }
      )
    end

    # Broadcast an error to conversation subscribers
    #
    # @param conversation [Ai::Conversation] The conversation
    # @param error_message [String] The error message
    def broadcast_error(conversation, error_message)
      stream_name = conversation.websocket_channel.presence || conversation_stream_name(conversation.id)

      ActionCable.server.broadcast(
        stream_name,
        {
          type: "error",
          conversation_id: conversation.conversation_id,
          message: error_message,
          timestamp: Time.current.iso8601
        }
      )
    end

    def conversation_stream_name(conversation_id)
      "ai_conversation:#{conversation_id}"
    end

    private

    # Serialize message for frontend consumption
    # Translates backend model format to frontend expected format
    def serialize_message(message)
      # Map role to sender_type for frontend compatibility
      sender_type = case message.role
      when "user" then "user"
      when "assistant" then "ai"
      when "system" then "system"
      else message.role
      end

      # Build sender_info from available data
      # Per-message agent attribution: use the message's own agent first,
      # then fall back to the conversation's primary agent
      sender_info = if message.user.present?
                      {
                        id: message.user.id,
                        name: message.user.name || message.user.full_name || message.user.email
                      }
      elsif message.assistant_message?
                      msg_agent = message.agent
                      {
                        id: msg_agent&.id,
                        name: msg_agent&.name || message.conversation&.agent&.name || "AI Assistant",
                        agent_type: msg_agent&.agent_type
                      }.compact
      else
                      {}
      end

      # Build metadata with token/cost info
      # streaming: false signals the frontend to exit streaming render mode
      metadata = {
        streaming: false,
        tokens_used: message.token_count,
        cost_estimate: message.cost_usd,
        processing: message.processing?,
        error: message.failed?,
        error_message: message.error_message
      }.compact

      # Merge content_metadata actions if present
      if message.respond_to?(:content_metadata) && message.content_metadata.present?
        metadata = metadata.merge(
          actions: message.content_metadata["actions"],
          action_context: message.content_metadata["action_context"],
          concierge_action: message.content_metadata["concierge_action"],
          action_params: message.content_metadata["action_params"],
          mentions: message.content_metadata["mentions"]
        ).compact
      end

      {
        id: message.message_id || message.id,
        content: message.content,
        sender_type: sender_type,
        sender_info: sender_info,
        sequence_number: message.sequence_number,
        created_at: message.created_at&.iso8601,
        metadata: metadata
      }
    end
  end

  private

  def conversation_stream_name(conversation_id)
    self.class.conversation_stream_name(conversation_id)
  end

  def authorized_for_conversation?(conversation)
    return false unless current_user

    # Use conversation's access check if available, otherwise fall back to account check
    if conversation.respond_to?(:can_access?)
      conversation.can_access?(current_user)
    else
      conversation.account_id == current_user.account_id
    end
  end

  def broadcast_message_created(message)
    self.class.broadcast_message_created(@conversation, message)
  end

  def broadcast_to_conversation(data)
    stream_name = @conversation.websocket_channel.presence || conversation_stream_name(@conversation.id)
    ActionCable.server.broadcast(stream_name, data)
  end

  def trigger_ai_response(user_message)
    # Dispatch AI response to worker service
    WorkerJobService.enqueue_ai_conversation_response(
      @conversation.id,
      user_message.id,
      current_user.id
    )

    transmit({
      type: "ai_response_queued",
      status: "queued",
      timestamp: Time.current.iso8601
    })
  rescue StandardError => e
    Rails.logger.error "[AiConversationChannel] Failed to queue AI response: #{e.message}"
    transmit({
      type: "ai_response_queued",
      status: "failed",
      error: "AI response could not be queued",
      timestamp: Time.current.iso8601
    })
  end

  def transmit_error(message)
    transmit({
      type: "error",
      message: message,
      timestamp: Time.current.iso8601
    })
  end
end
