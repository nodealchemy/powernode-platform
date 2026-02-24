# frozen_string_literal: true

module Ai
  module AgentHelpers
    extend ActiveSupport::Concern

    private

    def validate_permissions
      return if current_worker

      permission_map = {
        %w[index show my_agents public_agents agent_types statistics skills executions_index execution_show execution_logs conversations_index conversation_show conversation_messages stats analytics connections] => "ai.agents.read",
        %w[create clone assign_skill] => "ai.agents.create",
        %w[update validate] => "ai.agents.update",
        %w[destroy execution_destroy remove_skill] => "ai.agents.delete",
        %w[execute test pause resume archive execution_cancel execution_retry] => "ai.agents.execute",
        %w[conversation_create send_message] => "ai.conversations.create",
        %w[conversation_update pause_conversation resume_conversation complete_conversation regenerate] => "ai.conversations.update",
        %w[conversation_destroy] => "ai.conversations.delete",
        %w[archive_conversation export_conversation] => "ai.conversations.manage",
        %w[rate message_thread edit_history] => "ai.conversations.read",
        %w[edit_content reply_to_message] => "ai.conversations.update",
        %w[destroy_message restore_message] => "ai.conversations.delete"
      }

      permission_map.each do |actions, permission|
        return require_permission(permission) if actions.include?(action_name)
      end
    end

    def agent_params
      params.require(:agent).permit(
        :name, :description, :agent_type, :status, :system_prompt, :model_identifier,
        :temperature, :max_tokens, :top_p, :frequency_penalty, :presence_penalty,
        :is_public, :ai_provider_id,
        metadata: {}, mcp_tool_manifest: {}, mcp_input_schema: {}, mcp_output_schema: {}
      )
    end

    def agent_update_params
      params.require(:agent).permit(
        :name, :description, :status, :is_public, :ai_provider_id, :agent_type,
        # Model config - single source of truth via accessors
        :model, :temperature, :max_tokens, :system_prompt,
        :top_p, :frequency_penalty, :presence_penalty,
        metadata: {}, mcp_tool_manifest: {}, mcp_input_schema: {}, mcp_output_schema: {}, mcp_metadata: {}
      )
    end

    def apply_agent_sorting(collection)
      case params[:sort] || "updated_at"
      when "name" then collection.order(:name)
      when "created_at" then collection.order(created_at: :desc)
      when "last_executed" then collection.order(last_executed_at: :desc, created_at: :desc)
      when "agent_type" then collection.order(:agent_type, :name)
      else collection.order(updated_at: :desc)
      end
    end

    def agent_type_description(type)
      {
        "conversational" => "Interactive chat agents for natural conversations",
        "workflow" => "Agents designed for multi-step workflow execution",
        "automation" => "Task automation and process management agents",
        "content_generator" => "Content creation and generation agents",
        "code_assistant" => "Programming and code-related assistance",
        "data_analyzer" => "Data analysis and insights generation",
        "creative" => "Creative content and ideation agents",
        "specialist" => "Domain-specific specialist agents"
      }[type] || "Custom agent type"
    end
  end
end
