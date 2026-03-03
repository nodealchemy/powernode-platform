# frozen_string_literal: true

# Serialization methods for AI agents and related resources
#
# Provides standardized serialization for:
# - Agents (summary and detail)
# - Agent executions
# - Conversations
# - Messages
#
# Usage:
#   class AgentsController < ApplicationController
#     include Ai::AgentSerialization
#
#     def show
#       render_success(agent: serialize_agent_detail(@agent))
#     end
#   end
#
module Ai
  module AgentSerialization
    extend ActiveSupport::Concern

    private

    # =============================================================================
    # AGENT SERIALIZATION
    # =============================================================================

    def serialize_agent(agent)
      executions = agent.executions
      {
        id: agent.id,
        name: agent.name,
        description: agent.description,
        agent_type: agent.agent_type,
        status: agent.status,
        version: agent.version,
        is_public: agent.is_public,
        is_concierge: agent.is_concierge?,
        skill_slugs: agent.skill_slugs,
        created_at: agent.created_at.iso8601,
        updated_at: agent.updated_at.iso8601,
        last_executed_at: agent.last_executed_at&.iso8601,
        created_by: serialize_agent_user(agent.creator),
        provider: agent.provider ? serialize_agent_provider(agent.provider) : nil,
        # Model config - single source of truth via accessors
        model: agent.model,
        temperature: agent.temperature,
        max_tokens: agent.max_tokens,
        system_prompt: agent.system_prompt,
        full_system_prompt: agent.build_system_prompt_with_profile,
        # Legacy fields for backwards compatibility
        mcp_tool_manifest: agent.mcp_tool_manifest,
        mcp_input_schema: agent.mcp_input_schema,
        mcp_output_schema: agent.mcp_output_schema,
        mcp_metadata: agent.mcp_metadata,
        execution_stats: build_execution_stats(agent, executions)
      }
    end

    def serialize_agent_detail(agent)
      executions = agent.executions
      serialize_agent(agent).merge(
        metadata: agent.metadata,
        model_config: agent.model_config,
        skills: agent.agent_skills.includes(:skill).order(priority: :asc).map { |as|
          { id: as.skill.id, name: as.skill.name, slug: as.skill.slug,
            category: as.skill.category, is_active: as.is_active, priority: as.priority,
            command_count: as.skill.commands&.size || 0 }
        },
        detailed_stats: build_detailed_stats(executions)
      )
    end

    # =============================================================================
    # EXECUTION SERIALIZATION
    # =============================================================================

    def serialize_execution(execution)
      {
        id: execution.id,
        execution_id: execution.execution_id,
        status: execution.status,
        output_data: execution.output_data,
        created_at: execution.created_at.iso8601,
        started_at: execution.started_at&.iso8601,
        completed_at: execution.completed_at&.iso8601,
        duration_ms: execution.duration_ms,
        cost_usd: execution.cost_usd&.to_f,
        tokens_used: execution.tokens_used,
        agent: {
          id: execution.agent.id,
          name: execution.agent.name,
          agent_type: execution.agent.agent_type
        },
        user: execution.user ? serialize_agent_user(execution.user) : nil
      }
    end

    def serialize_execution_detail(execution)
      result = serialize_execution(execution).merge(
        input_parameters: execution.input_parameters,
        output_data: execution.output_data,
        execution_context: execution.execution_context,
        provider: execution.provider ? serialize_agent_provider_detail(execution.provider) : nil
      )
      result[:error_details] = execution.error_details if execution.error_details.present?
      result
    end

    # =============================================================================
    # CONVERSATION SERIALIZATION
    # =============================================================================

    def serialize_conversation(conversation)
      {
        id: conversation.id,
        conversation_id: conversation.conversation_id,
        title: conversation.title || "Conversation with #{conversation.provider.name}",
        status: conversation.status,
        message_count: conversation.message_count,
        total_tokens: conversation.total_tokens,
        total_cost: conversation.total_cost&.to_f,
        is_collaborative: conversation.is_collaborative?,
        participant_count: conversation.participants.size,
        created_at: conversation.created_at.iso8601,
        last_activity_at: conversation.last_activity_at&.iso8601,
        ai_agent: conversation.ai_agent ? { id: conversation.agent.id, name: conversation.agent.name, agent_type: conversation.agent.agent_type } : nil,
        provider: { id: conversation.provider.id, name: conversation.provider.name, provider_type: conversation.provider.provider_type },
        user: serialize_agent_user(conversation.user)
      }
    end

    def serialize_conversation_detail(conversation)
      serialize_conversation(conversation).merge(
        summary: conversation.summary,
        websocket_channel: conversation.websocket_channel,
        websocket_session_id: conversation.websocket_session_id,
        participants: conversation.is_collaborative? ? conversation.participant_users.map { |u| serialize_agent_user(u) } : [],
        recent_messages: conversation.messages.recent.limit(10).map { |m| serialize_message(m) },
        metadata: {
          can_send_message: conversation.can_send_message?,
          active_session: conversation.websocket_session_id.present?
        }
      )
    end

    def serialize_message(message)
      message.message_data
    end

    # =============================================================================
    # HELPER SERIALIZERS
    # =============================================================================

    def serialize_agent_user(user)
      return nil unless user
      { id: user.id, name: user.full_name, email: user.email }
    end

    def serialize_agent_provider(provider)
      {
        id: provider.id,
        name: provider.name,
        slug: provider.slug,
        provider_type: provider.provider_type
      }
    end

    def serialize_agent_provider_detail(provider)
      {
        id: provider.id,
        name: provider.name,
        provider_type: provider.provider_type
      }
    end

    def build_execution_stats(agent, executions)
      {
        total_executions: executions.size,
        successful_executions: executions.count { |e| e.status == "completed" },
        failed_executions: executions.count { |e| e.status == "failed" },
        success_rate: agent.success_rate || 0,
        avg_execution_time: executions.where.not(completed_at: nil).average("EXTRACT(epoch FROM (completed_at - started_at))")&.to_f&.round(2) || 0
      }
    end

    def build_detailed_stats(executions)
      total = executions.size
      completed = executions.count { |e| e.status == "completed" }
      {
        total_executions: total,
        successful_executions: completed,
        failed_executions: executions.count { |e| e.status == "failed" },
        average_duration: executions.where.not(completed_at: nil).average("EXTRACT(epoch FROM (completed_at - started_at))")&.to_f&.round(2) || 0,
        total_cost: executions.sum(:cost_usd)&.to_f&.round(4) || 0,
        success_rate: total.zero? ? 0 : ((completed.to_f / total) * 100).round(2)
      }
    end
  end
end
