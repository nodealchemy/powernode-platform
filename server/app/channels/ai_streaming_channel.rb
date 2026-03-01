# frozen_string_literal: true

# AiStreamingChannel - Real-time token streaming for AI responses
#
# Provides WebSocket delivery of individual tokens as they arrive
# from AI providers (OpenAI, Anthropic, Ollama).
#
# Subscription patterns:
#   # Subscribe to specific execution stream
#   channel.subscribe(execution_id: execution_id)
#
#   # Subscribe to conversation stream
#   channel.subscribe(conversation_id: conversation_id)
#
class AiStreamingChannel < ApplicationCable::Channel
  def subscribed
    execution_id = params[:execution_id]
    conversation_id = params[:conversation_id]

    if execution_id.present?
      subscribe_to_execution(execution_id)
    elsif conversation_id.present?
      subscribe_to_conversation(conversation_id)
    else
      reject
      return
    end

    Rails.logger.info "[AiStreamingChannel] Subscribed: user=#{current_user.id} execution=#{execution_id} conversation=#{conversation_id}"
  end

  def unsubscribed
    Rails.logger.info "[AiStreamingChannel] Unsubscribed: user=#{current_user.id}"
    stop_all_streams
  end

  # ==========================================================================
  # CLASS METHODS FOR BROADCASTING
  # ==========================================================================

  class << self
    # Broadcast stream start event
    #
    # @param stream_id [String] Unique stream identifier
    # @param execution_id [String] Execution ID (optional)
    # @param conversation_id [String] Conversation ID (optional)
    # @param metadata [Hash] Additional metadata
    def broadcast_stream_start(stream_id:, execution_id: nil, conversation_id: nil, **metadata)
      message = build_message("stream_start", {
        stream_id: stream_id,
        **metadata
      })

      broadcast_to_streams(message, execution_id: execution_id, conversation_id: conversation_id)
    end

    # Broadcast token/content delta
    #
    # @param stream_id [String] Unique stream identifier
    # @param content [String] New content chunk (token)
    # @param accumulated_content [String] Full accumulated content so far
    # @param chunk_index [Integer] Index of this chunk
    # @param execution_id [String] Execution ID (optional)
    # @param conversation_id [String] Conversation ID (optional)
    def broadcast_token(stream_id:, content:, accumulated_content:, chunk_index:, execution_id: nil, conversation_id: nil)
      message = build_message("token", {
        stream_id: stream_id,
        content: content,
        accumulated_content: accumulated_content,
        chunk_index: chunk_index
      })

      broadcast_to_streams(message, execution_id: execution_id, conversation_id: conversation_id)
    end

    # Broadcast stream completion
    #
    # @param stream_id [String] Unique stream identifier
    # @param content [String] Final complete content
    # @param usage [Hash] Token usage stats (prompt_tokens, completion_tokens, total_tokens)
    # @param cost [Float] Estimated cost
    # @param duration_ms [Integer] Total duration in milliseconds
    # @param execution_id [String] Execution ID (optional)
    # @param conversation_id [String] Conversation ID (optional)
    def broadcast_stream_end(stream_id:, content:, usage:, cost:, duration_ms:, execution_id: nil, conversation_id: nil)
      message = build_message("stream_end", {
        stream_id: stream_id,
        content: content,
        usage: usage,
        cost: cost,
        duration_ms: duration_ms
      })

      broadcast_to_streams(message, execution_id: execution_id, conversation_id: conversation_id)
    end

    # Broadcast stream error
    #
    # @param stream_id [String] Unique stream identifier
    # @param error [String] Error message
    # @param partial_content [String] Any content received before error
    # @param execution_id [String] Execution ID (optional)
    # @param conversation_id [String] Conversation ID (optional)
    def broadcast_stream_error(stream_id:, error:, partial_content: nil, execution_id: nil, conversation_id: nil)
      message = build_message("stream_error", {
        stream_id: stream_id,
        error: error,
        partial_content: partial_content
      })

      broadcast_to_streams(message, execution_id: execution_id, conversation_id: conversation_id)
    end

    private

    def build_message(event_type, payload)
      {
        type: event_type,
        data: payload,
        timestamp: Time.current.iso8601
      }
    end

    def broadcast_to_streams(message, execution_id:, conversation_id:)
      if execution_id.present?
        ActionCable.server.broadcast(
          "ai_streaming:execution:#{execution_id}",
          message
        )
      end

      if conversation_id.present?
        ActionCable.server.broadcast(
          "ai_streaming:conversation:#{conversation_id}",
          message
        )
      end
    end
  end

  private

  def subscribe_to_execution(execution_id)
    execution = Ai::AgentExecution.find_by(id: execution_id) ||
                Ai::AgentExecution.find_by(execution_id: execution_id)

    unless execution && authorized_for_execution?(execution)
      reject
      return
    end

    stream_from "ai_streaming:execution:#{execution_id}"

    transmit({
      type: "subscription.confirmed",
      subscription_type: "execution",
      execution_id: execution_id,
      timestamp: Time.current.iso8601
    })
  end

  def subscribe_to_conversation(conversation_id)
    conversation = AiConversation.find_by(id: conversation_id)

    unless conversation && authorized_for_conversation?(conversation)
      reject
      return
    end

    stream_from "ai_streaming:conversation:#{conversation_id}"

    transmit({
      type: "subscription.confirmed",
      subscription_type: "conversation",
      conversation_id: conversation_id,
      timestamp: Time.current.iso8601
    })
  end

  def authorized_for_execution?(execution)
    return false unless current_user

    execution.account_id == current_user.account_id
  end

  def authorized_for_conversation?(conversation)
    return false unless current_user

    conversation.account_id == current_user.account_id
  end
end
