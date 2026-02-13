# frozen_string_literal: true

# Conversation management actions: pin/unpin, bulk ops, search, worker callbacks
#
# Extracted from ConversationsController to keep it under 300 lines.
module Ai
  module ConversationManagementActions
    extend ActiveSupport::Concern

    # POST /api/v1/ai/conversations/:id/pin
    def pin
      @conversation.pin!

      render_success({
        conversation: serialize_conversation(@conversation),
        message: "Conversation pinned successfully"
      })

      log_audit_event("ai.conversations.pin", @conversation)
    rescue ActiveRecord::RecordInvalid => e
      render_error("Failed to pin conversation: #{e.message}", status: :unprocessable_content)
    end

    # DELETE /api/v1/ai/conversations/:id/unpin
    def unpin
      @conversation.unpin!

      render_success({
        conversation: serialize_conversation(@conversation),
        message: "Conversation unpinned successfully"
      })

      log_audit_event("ai.conversations.unpin", @conversation)
    rescue ActiveRecord::RecordInvalid => e
      render_error("Failed to unpin conversation: #{e.message}", status: :unprocessable_content)
    end

    # PATCH /api/v1/ai/conversations/bulk
    def bulk
      ids = params[:conversation_ids]
      return render_error("conversation_ids required", status: :bad_request) if ids.blank?

      conversations = current_user.account.ai_conversations.where(id: ids)
      return render_error("No conversations found", status: :not_found) if conversations.empty?

      action = params[:action_type]
      case action
      when "archive"
        conversations.update_all(status: "archived", updated_at: Time.current)
      when "delete"
        conversations.destroy_all
      when "tag"
        tag = params[:tag]&.strip&.downcase
        return render_error("tag required", status: :bad_request) if tag.blank?

        conversations.find_each { |c| c.add_tag(tag) }
      when "untag"
        tag = params[:tag]&.strip&.downcase
        return render_error("tag required", status: :bad_request) if tag.blank?

        conversations.find_each { |c| c.remove_tag(tag) }
      when "pin"
        conversations.update_all(pinned_at: Time.current, updated_at: Time.current)
      when "unpin"
        conversations.update_all(pinned_at: nil, updated_at: Time.current)
      else
        return render_error("Invalid action_type. Must be: archive, delete, tag, untag, pin, unpin", status: :bad_request)
      end

      render_success({
        affected_count: conversations.count,
        action: action,
        message: "Bulk #{action} completed successfully"
      })

      log_audit_event("ai.conversations.bulk_#{action}", nil, conversation_ids: ids)
    rescue StandardError => e
      render_error("Bulk operation failed: #{e.message}", status: :unprocessable_content)
    end

    # GET /api/v1/ai/conversations/search
    def search
      query = params[:q]
      return render_error("Search query required", status: :bad_request) if query.blank?

      conversations = ::Ai::Conversation
                        .search_messages(query, account_id: current_user.account_id)
                        .includes(:user, :agent, :provider)

      conversations = apply_pagination(conversations)

      render_success({
        conversations: conversations.map { |c| serialize_conversation(c) },
        pagination: pagination_data(conversations),
        query: query
      })
    rescue StandardError => e
      render_error("Search failed: #{e.message}", status: :unprocessable_content)
    end

    # POST /api/v1/ai/conversations/:id/worker_complete
    # Internal endpoint for worker to broadcast completed chat response
    def worker_complete
      conversation = current_account_conversations.find_by(id: params[:id]) ||
                     current_account_conversations.find_by(conversation_id: params[:id])
      return render_error("Conversation not found", status: :not_found) unless conversation

      content = params[:content]
      return render_error("Content required", status: :bad_request) if content.blank?

      assistant_message = conversation.add_assistant_message(
        content,
        message_type: "text",
        token_count: params[:token_count]&.to_i || 0,
        cost_usd: params[:cost_usd]&.to_f || 0.0,
        processing_metadata: {
          model: params[:model],
          duration_ms: params[:duration_ms],
          source: "worker"
        }
      )

      ActionCable.server.broadcast(
        conversation.websocket_channel,
        {
          type: "ai_response_complete",
          conversation_id: conversation.conversation_id,
          message: assistant_message.message_data
        }
      )

      render_success({ message_id: assistant_message.message_id })
    rescue StandardError => e
      render_error("Failed to complete: #{e.message}", status: :unprocessable_content)
    end

    # POST /api/v1/ai/conversations/:id/worker_stream_chunk
    # Internal endpoint for worker to broadcast streaming token chunks
    # No database write — chunks are transient, only worker_complete persists
    def worker_stream_chunk
      conversation = current_account_conversations.find_by(id: params[:id]) ||
                     current_account_conversations.find_by(conversation_id: params[:id])
      return render_error("Conversation not found", status: :not_found) unless conversation

      ActionCable.server.broadcast(
        conversation.websocket_channel,
        {
          type: "ai_response_streaming",
          conversation_id: conversation.conversation_id,
          message: {
            id: params[:message_id] || "streaming-#{conversation.id}",
            content: params[:accumulated_content] || "",
            sender_type: "ai",
            sender_info: { name: params[:agent_name] || "AI Assistant" },
            created_at: Time.current.iso8601,
            metadata: {
              streaming: true,
              tokens_used: params[:token_count]&.to_i || 0,
              model: params[:model],
              sequence: params[:sequence]&.to_i || 0
            }
          }
        }
      )

      render_success({ broadcast: true })
    rescue StandardError => e
      render_error("Failed to broadcast chunk: #{e.message}", status: :unprocessable_content)
    end

    # POST /api/v1/ai/conversations/:id/worker_error
    # Internal endpoint for worker to broadcast error
    def worker_error
      conversation = current_account_conversations.find_by(id: params[:id]) ||
                     current_account_conversations.find_by(conversation_id: params[:id])
      return render_error("Conversation not found", status: :not_found) unless conversation

      ActionCable.server.broadcast(
        conversation.websocket_channel,
        {
          type: "error",
          conversation_id: conversation.conversation_id,
          error: params[:error] || "Unknown error"
        }
      )

      render_success({ broadcast: true })
    rescue StandardError => e
      render_error("Failed to broadcast error: #{e.message}", status: :unprocessable_content)
    end

    private

    def current_account_conversations
      current_user&.account&.ai_conversations || ::Ai::Conversation.none
    end
  end
end
