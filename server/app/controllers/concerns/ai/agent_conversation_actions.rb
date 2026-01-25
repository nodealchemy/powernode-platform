# frozen_string_literal: true

# Actions for managing agent conversations
#
# Provides CRUD and lifecycle actions for conversations nested under agents:
# - List, show, create, update, destroy conversations
# - Conversation lifecycle: pause, resume, complete, archive
# - Message sending and management
# - Conversation export
#
# Requires:
# - @agent to be set (use before_action :set_agent)
# - conversation_service method to be defined
# - AgentSerialization concern for serialization methods
#
# Usage:
#   class AgentsController < ApplicationController
#     include Ai::AgentConversationActions
#     include Ai::AgentSerialization
#
#     before_action :set_agent, only: [:conversations_index, :conversation_show, ...]
#
#     private
#
#     def conversation_service
#       @conversation_service ||= ::Ai::Agents::ConversationService.new(agent: @agent, user: current_user)
#     end
#   end
#
module Ai
  module AgentConversationActions
    extend ActiveSupport::Concern

    # =============================================================================
    # CONVERSATION CRUD
    # =============================================================================

    # GET /api/v1/ai/agents/:agent_id/conversations
    def conversations_index
      conversations = @agent.conversations.includes(:user, :provider).order(last_activity_at: :desc)
      conversations = apply_pagination(conversations)

      render_success(
        conversations: conversations.map { |c| serialize_conversation(c) },
        pagination: pagination_data(conversations)
      )
    end

    # GET /api/v1/ai/agents/:agent_id/conversations/:conversation_id
    def conversation_show
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      render_success(conversation: serialize_conversation_detail(conversation))
    end

    # POST /api/v1/ai/agents/:agent_id/conversations
    def conversation_create
      result = conversation_service.create(conversation_params)

      if result.success?
        render_success({ conversation: serialize_conversation_detail(result.data[:conversation]) }, status: :created)
        log_audit_event("ai.conversations.create", result.data[:conversation])
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # PATCH /api/v1/ai/agents/:agent_id/conversations/:conversation_id
    def conversation_update
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      result = conversation_service.update(conversation, conversation_params)

      if result.success?
        render_success(conversation: serialize_conversation(result.data[:conversation]))
        log_audit_event("ai.conversations.update", conversation)
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # DELETE /api/v1/ai/agents/:agent_id/conversations/:conversation_id
    def conversation_destroy
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      result = conversation_service.destroy(conversation)

      if result.success?
        render_success(message: result.data[:message])
        log_audit_event("ai.conversations.delete", conversation)
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # =============================================================================
    # CONVERSATION MESSAGING
    # =============================================================================

    # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/send_message
    def send_message
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      result = conversation_service.send_message(
        conversation,
        content: params[:content],
        metadata: params[:metadata] || {}
      )

      if result.success?
        render_success(message: serialize_message(result.data[:message]))
        log_audit_event("ai.conversations.message.send", result.data[:message])
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # GET /api/v1/ai/agents/:agent_id/conversations/:conversation_id/messages
    def conversation_messages
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      messages = conversation.messages.order(created_at: :asc)

      render_success(messages: messages.map { |m| serialize_message(m) })
    end

    # =============================================================================
    # CONVERSATION LIFECYCLE
    # =============================================================================

    # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/pause
    def pause_conversation
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      result = conversation_service.pause(conversation)

      render_success(
        conversation: serialize_conversation(result.data[:conversation]),
        message: "Conversation paused successfully"
      )
      log_audit_event("ai.conversations.pause", conversation)
    end

    # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/resume
    def resume_conversation
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      result = conversation_service.resume(conversation)

      render_success(
        conversation: serialize_conversation(result.data[:conversation]),
        message: "Conversation resumed successfully"
      )
      log_audit_event("ai.conversations.resume", conversation)
    end

    # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/complete
    def complete_conversation
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      result = conversation_service.complete(conversation)

      render_success(
        conversation: serialize_conversation(result.data[:conversation]),
        message: "Conversation completed successfully"
      )
      log_audit_event("ai.conversations.complete", conversation)
    end

    # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/archive
    def archive_conversation
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      result = conversation_service.archive(conversation)

      render_success(
        conversation: serialize_conversation(result.data[:conversation]),
        message: "Conversation archived successfully"
      )
      log_audit_event("ai.conversations.archive", conversation)
    end

    # =============================================================================
    # CONVERSATION EXPORT
    # =============================================================================

    # GET /api/v1/ai/agents/:agent_id/conversations/:conversation_id/export
    def export_conversation
      conversation = @agent.conversations.find(params[:conversation_id] || params[:id])
      export_data = conversation_service.export(conversation, format: params[:format] || "json")

      render_success(
        conversation: serialize_conversation_detail(export_data[:conversation]),
        export_format: export_data[:export_format],
        exported_at: export_data[:exported_at]
      )
      log_audit_event("ai.conversations.export", conversation)
    end

    # =============================================================================
    # MESSAGE ACTIONS
    # =============================================================================

    # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/messages/:id/regenerate
    def regenerate
      set_agent unless @agent
      return if performed?

      conversation = @agent.conversations.find(params[:conversation_id])
      message = conversation.messages.find(params[:id])
      result = conversation_service.regenerate_message(conversation, message)

      if result.success?
        render_success(
          message: serialize_message(result.data[:message]),
          regeneration_queued: result.data[:regeneration_queued],
          regeneration_request: result.data[:regeneration_request]
        )
        log_audit_event("ai.messages.regenerate", message)
      else
        render_error(result.error, status: :unprocessable_content)
      end
    rescue ActiveRecord::RecordNotFound => e
      render_error(e.message, status: :not_found)
    end

    # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/messages/:id/rate
    def rate
      set_agent unless @agent
      return if performed?

      conversation = @agent.conversations.find(params[:conversation_id])
      message = conversation.messages.find(params[:id])
      result = conversation_service.rate_message(
        message,
        rating: params[:rating],
        feedback: params[:feedback]
      )

      if result.success?
        render_success(
          message: serialize_message(result.data[:message]),
          rating: result.data[:rating]
        )
        log_audit_event("ai.messages.rate", message, rating: params[:rating])
      else
        render_error(result.error, status: :unprocessable_content)
      end
    rescue ActiveRecord::RecordNotFound => e
      render_error(e.message, status: :not_found)
    end

    private

    # Conversation parameter handling (can be overridden in including controller)
    def conversation_params
      params.require(:conversation).permit(:title, :status, :is_collaborative, participants: [])
    end
  end
end
