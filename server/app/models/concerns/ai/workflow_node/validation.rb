# frozen_string_literal: true

module Ai
  class WorkflowNode
    module Validation
      extend ActiveSupport::Concern

      included do
        validate :validate_node_configuration
        validate :validate_consolidated_node_action
      end

      private

      def validate_node_configuration
        return unless configuration.present?

        case node_type
        when "ai_agent"
          validate_ai_agent_configuration
        when "api_call"
          validate_api_call_configuration
        when "webhook"
          validate_webhook_configuration
        when "condition"
          validate_condition_configuration
        when "loop"
          validate_loop_configuration
        when "delay"
          validate_delay_configuration
        when "human_approval"
          validate_human_approval_configuration
        when "sub_workflow"
          validate_sub_workflow_configuration
        when "kb_article"
          validate_kb_article_configuration
        when "page"
          validate_page_configuration
        when "mcp_operation"
          validate_mcp_operation_configuration
        when "ralph_loop"
          validate_ralph_loop_configuration
        end
      end

      def validate_consolidated_node_action
        case node_type
        when "kb_article"
          action = configuration["action"]
          unless Ai::WorkflowNode::KB_ARTICLE_ACTIONS.include?(action)
            errors.add(:configuration, "action must be one of: #{Ai::WorkflowNode::KB_ARTICLE_ACTIONS.join(', ')}")
          end
        when "page"
          action = configuration["action"]
          unless Ai::WorkflowNode::PAGE_ACTIONS.include?(action)
            errors.add(:configuration, "action must be one of: #{Ai::WorkflowNode::PAGE_ACTIONS.join(', ')}")
          end
        when "mcp_operation"
          operation_type = configuration["operation_type"]
          unless Ai::WorkflowNode::MCP_OPERATION_TYPES.include?(operation_type)
            errors.add(:configuration, "operation_type must be one of: #{Ai::WorkflowNode::MCP_OPERATION_TYPES.join(', ')}")
          end
        when "ralph_loop"
          operation = configuration["operation"]
          unless Ai::WorkflowNode::RALPH_LOOP_OPERATIONS.include?(operation)
            errors.add(:configuration, "operation must be one of: #{Ai::WorkflowNode::RALPH_LOOP_OPERATIONS.join(', ')}")
          end
        end
      end

      def validate_ai_agent_configuration
        if configuration["agent_id"].blank?
          errors.add(:configuration, "must specify an agent_id for AI agent nodes")
        elsif !workflow.account.ai_agents.exists?(id: configuration["agent_id"])
          errors.add(:configuration, "specified agent_id does not exist")
        end
      end

      def validate_api_call_configuration
        if configuration["url"].blank?
          errors.add(:configuration, "must specify a URL for API call nodes")
        end

        unless %w[GET POST PUT PATCH DELETE].include?(configuration["method"])
          errors.add(:configuration, "must specify a valid HTTP method")
        end
      end

      def validate_webhook_configuration
        if configuration["url"].blank?
          errors.add(:configuration, "must specify a URL for webhook nodes")
        end
      end

      def validate_condition_configuration
        if configuration["conditions"].blank? || !configuration["conditions"].is_a?(Array)
          errors.add(:configuration, "must specify conditions array for condition nodes")
        end
      end

      def validate_loop_configuration
        if configuration["iteration_source"].blank?
          errors.add(:configuration, "must specify iteration_source for loop nodes")
        end

        max_iterations = configuration["max_iterations"]
        if max_iterations.present? && (!max_iterations.is_a?(Integer) || max_iterations <= 0)
          errors.add(:configuration, "max_iterations must be a positive integer")
        end
      end

      def validate_delay_configuration
        delay_seconds = configuration["delay_seconds"]
        if configuration["delay_type"] == "fixed" && (!delay_seconds.is_a?(Integer) || delay_seconds <= 0)
          errors.add(:configuration, "delay_seconds must be a positive integer for fixed delays")
        end
      end

      def validate_human_approval_configuration
        if configuration["approvers"].blank? || !configuration["approvers"].is_a?(Array)
          errors.add(:configuration, "must specify approvers array for human approval nodes")
        end
      end

      def validate_sub_workflow_configuration
        if configuration["workflow_id"].blank?
          errors.add(:configuration, "must specify workflow_id for sub-workflow nodes")
        elsif !workflow.account.ai_workflows.exists?(id: configuration["workflow_id"])
          errors.add(:configuration, "specified workflow_id does not exist")
        end
      end

      def validate_kb_article_configuration
        action = configuration["action"]

        case action
        when "read", "update", "publish"
          if configuration["article_id"].blank?
            errors.add(:configuration, "must specify article_id for KB article #{action} action")
          end
        when "search"
          if configuration["search_query"].blank?
            errors.add(:configuration, "must specify search_query for KB article search action")
          end
        when "create"
          if configuration["title"].blank?
            errors.add(:configuration, "must specify title for KB article create action")
          end
        end
      end

      def validate_page_configuration
        action = configuration["action"]

        case action
        when "read", "update", "publish"
          if configuration["page_id"].blank?
            errors.add(:configuration, "must specify page_id for page #{action} action")
          end
        when "create"
          if configuration["title"].blank?
            errors.add(:configuration, "must specify title for page create action")
          end
        end
      end

      def validate_mcp_operation_configuration
        if configuration["mcp_server_id"].blank?
          errors.add(:configuration, "must specify mcp_server_id for MCP operation nodes")
        elsif !workflow.account.mcp_servers.exists?(id: configuration["mcp_server_id"])
          errors.add(:configuration, "specified MCP server does not exist")
        end

        operation_type = configuration["operation_type"]

        case operation_type
        when "tool"
          if configuration["mcp_tool_id"].blank? && configuration["mcp_tool_name"].blank?
            errors.add(:configuration, "must specify mcp_tool_id or mcp_tool_name for MCP tool operation")
          end

          unless %w[sync async].include?(configuration["execution_mode"])
            errors.add(:configuration, "execution_mode must be sync or async")
          end
        when "resource"
          if configuration["resource_uri"].blank?
            errors.add(:configuration, "must specify resource_uri for MCP resource operation")
          end
        when "prompt"
          if configuration["prompt_name"].blank?
            errors.add(:configuration, "must specify prompt_name for MCP prompt operation")
          end
        end
      end

      def validate_ralph_loop_configuration
        operation = configuration["operation"]

        case operation
        when "create"
          validate_ralph_loop_create_config
        when "start", "run_iteration", "run_to_completion", "pause", "resume", "cancel", "status", "get_learnings"
          validate_ralph_loop_instance_config
        when "add_task"
          validate_ralph_loop_add_task_config
        when "parse_prd"
          validate_ralph_loop_parse_prd_config
        end
      end

      def validate_ralph_loop_create_config
        if configuration["name"].blank?
          errors.add(:configuration, "must specify name for Ralph Loop create operation")
        end

        if configuration["ai_tool"].blank?
          errors.add(:configuration, "must specify ai_tool for Ralph Loop create operation")
        elsif !Ai::RalphLoop::AI_TOOLS.include?(configuration["ai_tool"])
          errors.add(:configuration, "ai_tool must be one of: #{Ai::RalphLoop::AI_TOOLS.join(', ')}")
        end

        max_iterations = configuration["max_iterations"]
        if max_iterations.present? && (!max_iterations.is_a?(Integer) || max_iterations <= 0)
          errors.add(:configuration, "max_iterations must be a positive integer")
        end
      end

      def validate_ralph_loop_instance_config
        # Loop can be specified by ID or variable reference
        if configuration["loop_id"].blank? && configuration["loop_variable"].blank?
          errors.add(:configuration, "must specify loop_id or loop_variable for Ralph Loop operation")
        end

        if configuration["loop_id"].present? && !workflow.account.ai_ralph_loops.exists?(id: configuration["loop_id"])
          errors.add(:configuration, "specified Ralph Loop does not exist")
        end

        # Validate operation-specific options
        operation = configuration["operation"]

        if operation == "run_to_completion"
          max_iterations = configuration["max_iterations"]
          if max_iterations.present? && (!max_iterations.is_a?(Integer) || max_iterations <= 0)
            errors.add(:configuration, "max_iterations must be a positive integer")
          end

          timeout_seconds = configuration["timeout_seconds"]
          if timeout_seconds.present? && (!timeout_seconds.is_a?(Integer) || timeout_seconds <= 0)
            errors.add(:configuration, "timeout_seconds must be a positive integer")
          end
        end

        if operation == "cancel" && configuration["reason"].present?
          if !configuration["reason"].is_a?(String) || configuration["reason"].length > 500
            errors.add(:configuration, "cancel reason must be a string of max 500 characters")
          end
        end
      end

      def validate_ralph_loop_add_task_config
        validate_ralph_loop_instance_config

        if configuration["task_key"].blank?
          errors.add(:configuration, "must specify task_key for add_task operation")
        end

        if configuration["description"].blank?
          errors.add(:configuration, "must specify description for add_task operation")
        end

        priority = configuration["priority"]
        if priority.present? && (!priority.is_a?(Integer) || priority < 0)
          errors.add(:configuration, "priority must be a non-negative integer")
        end
      end

      def validate_ralph_loop_parse_prd_config
        validate_ralph_loop_instance_config

        if configuration["prd_data"].blank? && configuration["prd_variable"].blank?
          errors.add(:configuration, "must specify prd_data or prd_variable for parse_prd operation")
        end
      end
    end
  end
end
