# frozen_string_literal: true

module AiWorkflowNode::ConfigurationHelpers
  extend ActiveSupport::Concern

  included do
    before_validation :set_default_configuration
  end

  # Configuration helpers
  def ai_agent
    return nil unless ai_agent_node? && configuration["agent_id"].present?

    ai_workflow.account.ai_agents.find_by(id: configuration["agent_id"])
  end

  def required_inputs
    validation_rules["required_inputs"] || []
  end

  def expected_outputs
    validation_rules["expected_outputs"] || []
  end

  def timeout_duration
    timeout_seconds || 300
  end

  def max_retries
    retry_count || 0
  end

  # Configuration management
  def update_configuration(new_config)
    merged_config = configuration.deep_merge(new_config)
    update!(configuration: merged_config)
  end

  def reset_configuration
    update!(configuration: default_configuration_for_type)
  end

  def valid_configuration_for_type?
    case node_type
    when "ai_agent"
      configuration["agent_id"].present?
    when "api_call"
      configuration["url"].present? && configuration["method"].present?
    when "webhook"
      configuration["url"].present?
    when "condition"
      configuration["conditions"].present?
    when "delay"
      configuration["delay_seconds"].present? || configuration["delay_expression"].present?
    when "kb_article"
      AiWorkflowNode::KB_ARTICLE_ACTIONS.include?(configuration["action"])
    when "page"
      AiWorkflowNode::PAGE_ACTIONS.include?(configuration["action"])
    when "mcp_operation"
      AiWorkflowNode::MCP_OPERATION_TYPES.include?(configuration["operation_type"]) &&
        configuration["mcp_server_id"].present?
    else
      true
    end
  end

  private

  def set_default_configuration
    return if configuration.present?

    self.configuration = default_configuration_for_type
  end

  def default_configuration_for_type
    case node_type
    when "ai_agent"
      ai_agent_default_config
    when "api_call"
      api_call_default_config
    when "webhook"
      webhook_default_config
    when "condition"
      condition_default_config
    when "loop"
      loop_default_config
    when "transform"
      transform_default_config
    when "delay"
      delay_default_config
    when "human_approval"
      human_approval_default_config
    when "sub_workflow"
      sub_workflow_default_config
    when "merge"
      merge_default_config
    when "split"
      split_default_config
    when "start"
      start_default_config
    when "end"
      end_default_config
    when "trigger"
      trigger_default_config
    when "kb_article"
      kb_article_default_config
    when "page"
      page_default_config
    when "mcp_operation"
      mcp_operation_default_config
    else
      {}
    end
  end

  def ai_agent_default_config
    {
      "agent_id" => nil,
      "temperature" => 0.7,
      "max_tokens" => 1000,
      "input_mapping" => {
        "prompt" => "input",
        "context" => "context",
        "data" => "data"
      },
      "output_mapping" => {
        "output" => "response",
        "result" => "response",
        "data" => "response"
      },
      "input_variables" => [ "input", "context", "data" ],
      "output_variables" => [ "output", "result", "data" ],
      "context_variables" => [ "input", "context", "data" ]
    }
  end

  def api_call_default_config
    {
      "method" => "GET",
      "url" => "",
      "headers" => {},
      "body" => {
        "input" => "{{input}}",
        "data" => "{{data}}"
      },
      "response_mapping" => {
        "output" => "body",
        "result" => "body.result",
        "data" => "body.data"
      }
    }
  end

  def webhook_default_config
    {
      "url" => "",
      "method" => "POST",
      "headers" => {
        "Content-Type" => "application/json"
      },
      "payload_template" => {
        "input" => "{{input}}",
        "data" => "{{data}}",
        "context" => "{{context}}"
      }
    }
  end

  def condition_default_config
    {
      "conditions" => [],
      "logic_operator" => "AND",
      "default_path" => "false",
      "input_variable" => "input",
      "output_mapping" => {
        "output" => "input",
        "result" => "condition_result",
        "data" => "input"
      }
    }
  end

  def loop_default_config
    {
      "iteration_source" => "data.items",
      "item_variable" => "item",
      "max_iterations" => 1000,
      "parallel" => false,
      "output_mapping" => {
        "output" => "results",
        "result" => "results",
        "data" => "results"
      }
    }
  end

  def transform_default_config
    {
      "transformations" => [
        { "output" => "{{input}}" },
        { "result" => "{{data}}" }
      ],
      "output_format" => "json",
      "input_mapping" => {
        "source" => "input",
        "data" => "data"
      },
      "output_mapping" => {
        "output" => "transformed",
        "result" => "transformed",
        "data" => "transformed"
      }
    }
  end

  def delay_default_config
    {
      "delay_type" => "fixed",
      "delay_seconds" => 60,
      "delay_expression" => "",
      "pass_through_data" => true,
      "output_mapping" => {
        "output" => "input",
        "result" => "input",
        "data" => "data"
      }
    }
  end

  def human_approval_default_config
    {
      "approval_message" => "Please review: {{input}}",
      "approvers" => [],
      "timeout_action" => "reject",
      "notification_template" => "Approval needed for: {{data}}",
      "output_mapping" => {
        "output" => "approval_result",
        "result" => "approval_result",
        "data" => "input_data",
        "approved" => "approved"
      }
    }
  end

  def sub_workflow_default_config
    {
      "workflow_id" => nil,
      "input_mapping" => {
        "input" => "input",
        "data" => "data",
        "context" => "context"
      },
      "output_mapping" => {
        "output" => "output",
        "result" => "result",
        "data" => "data"
      },
      "wait_for_completion" => true
    }
  end

  def merge_default_config
    {
      "merge_strategy" => "wait_all",
      "output_format" => "array",
      "timeout_seconds" => 3600,
      "output_mapping" => {
        "output" => "merged_data",
        "result" => "merged_data",
        "data" => "merged_data"
      }
    }
  end

  def split_default_config
    {
      "split_strategy" => "parallel",
      "branches" => [],
      "condition_variable" => "input",
      "output_mapping" => {
        "output" => "input",
        "data" => "data"
      }
    }
  end

  def start_default_config
    {
      "start_type" => "manual",
      "delay_seconds" => 0,
      "output_mapping" => {
        "output" => "start_data",
        "data" => "start_data"
      }
    }
  end

  def end_default_config
    {
      "end_type" => "success",
      "success_message" => "",
      "failure_message" => "",
      "artifacts" => []
    }
  end

  def trigger_default_config
    {
      "trigger_type" => "manual",
      "webhook_url" => "",
      "schedule" => "",
      "event_type" => "",
      "output_mapping" => {
        "output" => "trigger_data",
        "data" => "trigger_data"
      }
    }
  end

  def kb_article_default_config
    {
      "action" => "create",
      "article_id" => nil,
      "title" => "",
      "content" => "",
      "category_id" => nil,
      "tags" => [],
      "status" => "draft",
      "search_query" => "",
      "output_mapping" => {
        "output" => "result",
        "result" => "result",
        "data" => "result"
      }
    }
  end

  def page_default_config
    {
      "action" => "create",
      "page_id" => nil,
      "title" => "",
      "slug" => "",
      "content" => "",
      "status" => "draft",
      "meta_description" => "",
      "meta_keywords" => "",
      "output_mapping" => {
        "output" => "result",
        "result" => "result",
        "data" => "result"
      }
    }
  end

  def mcp_operation_default_config
    {
      "operation_type" => "tool",
      "mcp_server_id" => nil,
      "mcp_server_name" => nil,
      "mcp_tool_id" => nil,
      "mcp_tool_name" => nil,
      "execution_mode" => "sync",
      "parameters" => {},
      "parameter_mappings" => [],
      "resource_uri" => "",
      "prompt_name" => "",
      "arguments" => {},
      "argument_mappings" => [],
      "output_variable" => "prompt_result",
      "output_mapping" => {
        "output" => "messages",
        "result" => "messages",
        "data" => "data"
      }
    }
  end
end
