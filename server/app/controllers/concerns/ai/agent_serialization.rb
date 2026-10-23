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
        # MCP registration fields: live ai_agents columns, read by the agent
        # config tab (AgentConfigTab) and typed in shared/types/ai.ts.
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
        error_message: execution.error_message,
        input_summary: execution_input_summary(execution),
        output_summary: execution_output_summary(execution),
        model: execution_model(execution),
        source: execution_source(execution),
        executor: execution_executor(execution),
        agent: {
          id: execution.agent.id,
          name: execution.agent.name,
          agent_type: execution.agent.agent_type
        },
        user: execution.user ? serialize_agent_user(execution.user) : nil
      }
    end

    EXECUTION_SUMMARY_CHARS = 200

    # Claude Code rows keep a redacted task_digest; platform runs keep the
    # prompt as input_parameters["input"] (McpAgentExecutor) or as chat
    # messages (TrackedWorkerLlmClient). Read-only: nothing new is stored.
    def execution_input_summary(execution)
      params = execution.input_parameters
      return nil unless params.is_a?(Hash)

      text = params["task_digest"].presence || params["input"].presence || params["prompt"].presence
      text ||= last_user_message(params["messages"])
      summarize_execution_text(text)
    end

    # Platform runs write output_data["response"] (Agent#execute),
    # ["content"] (TrackedWorkerLlmClient) or an "error" string; Claude Code
    # rows carry only model_used, so they have no output text.
    def execution_output_summary(execution)
      data = execution.output_data
      return nil unless data.is_a?(Hash)

      summarize_execution_text(data["response"].presence || data["content"].presence ||
                               data["output"].presence || data["error"].presence)
    end

    def execution_model(execution)
      metrics = execution.performance_metrics.is_a?(Hash) ? execution.performance_metrics : {}
      data = execution.output_data.is_a?(Hash) ? execution.output_data : {}
      context = execution.execution_context.is_a?(Hash) ? execution.execution_context : {}
      (metrics["served_by"] || metrics["model"] || data["model_used"] || data.dig("metadata", "model_used") ||
        context["reported_model"]).presence
    end

    # nil when the row never recorded one: older platform rows did not stamp it.
    def execution_source(execution)
      context = execution.execution_context.is_a?(Hash) ? execution.execution_context : {}
      context["source"].presence
    end

    def execution_executor(execution)
      context = execution.execution_context.is_a?(Hash) ? execution.execution_context : {}
      kind = context["executor_kind"].presence
      agent_id = context["executor_agent_id"].presence
      return nil if kind.nil? && agent_id.nil?

      { kind: kind, agent_id: agent_id }.compact
    end

    def last_user_message(messages)
      return nil unless messages.is_a?(Array)

      msg = messages.reverse.find { |m| m.is_a?(Hash) && m["role"].to_s == "user" }
      msg && msg["content"]
    end

    def summarize_execution_text(text)
      return nil if text.blank?

      redact_execution_text(text.to_s.strip).truncate(EXECUTION_SUMMARY_CHARS)
    end

    # The detail door shows stored prompts and responses. Key-based masking
    # (Ai::SensitiveParams.filter) plus the text filter on every string leaf,
    # the deferred-operation envelope treatment, then the PII path for what has
    # no key beside it (an email address).
    def redact_execution_envelope(envelope)
      return envelope unless envelope.is_a?(Hash) || envelope.is_a?(Array)

      ::Ai::SensitiveParams.batch do
        redact_execution_leaves(::Ai::SensitiveParams.filter(envelope))
      end
    end

    def redact_execution_leaves(node)
      case node
      when ::Hash then node.transform_values { |value| redact_execution_leaves(value) }
      when ::Array then node.map { |value| redact_execution_leaves(value) }
      when ::String then redact_execution_text(node)
      else node
      end
    end

    def redact_execution_text(text)
      filtered = ::Ai::SensitiveParams.filter_text(text, truncate: false)
      ::Ai::Security::PiiRedactionService.new(account: current_user.account)
                                         .redact(text: filtered, context: { source_type: "AgentExecutionDetail" }, log: false)[:redacted_text]
    end

    def serialize_execution_detail(execution)
      result = serialize_execution(execution).merge(
        input_parameters: redact_execution_envelope(execution.input_parameters),
        output_data: redact_execution_envelope(execution.output_data),
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

    # default_model is the one the platform would use for an unpinned agent:
    # Provider#default_model, i.e. the configured default, else the
    # LIGHTEST-tier model in the synced catalog (E3b). The worker's streaming
    # concern (AiResponseJobConcern) reads exactly this key; before E3b it was
    # absent, so an unpinned agent could only fall through to a literal (and,
    # briefly, to catalog[0]). Nil means no model resolves, and the worker
    # refuses rather than guess.
    def serialize_agent_provider(provider)
      {
        id: provider.id,
        name: provider.name,
        slug: provider.slug,
        provider_type: provider.provider_type,
        default_model: provider.default_model.presence
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
        avg_execution_time: executions.where.not(completed_at: nil).average("EXTRACT(epoch FROM (completed_at - started_at))")&.to_f&.round(2) || 0,
        # HIER-P1C: runs the platform's own executor performed vs runs a Claude
        # Code session performed locally and reported back (both count above).
        by_executor_kind: executions_by_executor_kind(executions)
      }
    end

    def executions_by_executor_kind(executions)
      claude_code = executions.count { |e| e.claude_code_run? }
      { platform: executions.size - claude_code, claude_code: claude_code }
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
