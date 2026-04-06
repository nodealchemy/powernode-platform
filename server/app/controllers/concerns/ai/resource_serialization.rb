# frozen_string_literal: true

# Shared serialization methods for AI resources
#
# This concern provides standardized serialization for:
# - Agents and agent details
# - Execution logs
#
# Usage:
#   class AgentsController < ApplicationController
#     include Ai::ResourceSerialization
#
#     def show
#       render_success(agent: serialize_agent_detail(@agent))
#     end
#   end
#
module Ai
  module ResourceSerialization
    extend ActiveSupport::Concern

    # =============================================================================
    # AGENT SERIALIZATION
    # =============================================================================

    # Serialize agent for list views
    # @param agent [Ai::Agent] The agent to serialize
    # @return [Hash] Serialized agent data
    def serialize_agent(agent)
      {
        id: agent.id,
        name: agent.name,
        description: agent.description,
        agent_type: agent.agent_type,
        status: agent.status,
        is_active: agent.is_active,
        version: agent.version,
        tags: agent.metadata&.dig("tags") || [],
        created_at: agent.created_at.iso8601,
        updated_at: agent.updated_at.iso8601,
        stats: {
          executions_count: agent.executions.count,
          success_rate: calculate_agent_success_rate(agent),
          avg_response_time: calculate_agent_avg_response_time(agent)
        }
      }
    end

    # Serialize agent with full details
    # @param agent [Ai::Agent] The agent to serialize
    # @return [Hash] Detailed serialized agent data
    def serialize_agent_detail(agent)
      base = serialize_agent(agent)
      base.merge(
        system_prompt: agent.system_prompt,
        configuration: agent.configuration,
        model_settings: agent.model_settings,
        capabilities: agent.capabilities || [],
        tools: agent.tools || [],
        metadata: agent.metadata || {},
        provider: agent.provider ? {
          id: agent.provider.id,
          name: agent.provider.name,
          provider_type: agent.provider.provider_type
        } : nil,
        created_by: agent.creator ? serialize_user_compact(agent.creator) : nil
      )
    end

    # =============================================================================
    # EXECUTION LOG SERIALIZATION
    # =============================================================================

    # Serialize execution log
    # @param log [Ai::ExecutionLog] The log to serialize
    # @return [Hash] Serialized log data
    def serialize_log(log)
      {
        id: log.id,
        level: log.log_level,
        message: log.message,
        event_type: log.event_type,
        context_data: log.context_data,
        metadata: log.metadata,
        created_at: log.created_at.iso8601,
        node_execution: log.node_execution ? {
          execution_id: log.node_execution.execution_id,
          node_name: log.node_execution.node.name,
          node_type: log.node_execution.node.node_type
        } : nil
      }
    end

    # =============================================================================
    # USER SERIALIZATION
    # =============================================================================

    # Serialize user in compact format (for nested objects)
    # @param user [User] The user to serialize
    # @return [Hash] Compact serialized user data
    def serialize_user_compact(user)
      return nil unless user

      {
        id: user.id,
        name: user.full_name,
        email: user.email
      }
    end

    private

    # Calculate agent success rate
    # @param agent [Ai::Agent] The agent
    # @return [Float, nil] Success rate as decimal (0.0-1.0) or nil if no executions
    def calculate_agent_success_rate(agent)
      return nil unless agent.executions.exists?

      total = agent.executions.count
      successful = agent.executions.where(status: "completed").count
      (successful.to_f / total).round(4)
    end

    # Calculate agent average response time in milliseconds
    # @param agent [Ai::Agent] The agent
    # @return [Float, nil] Average response time in ms or nil if no data
    def calculate_agent_avg_response_time(agent)
      completed = agent.executions.where(status: "completed").where.not(duration_ms: nil)
      return nil unless completed.exists?

      completed.average(:duration_ms).to_f.round(2)
    end
  end
end
