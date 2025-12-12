# frozen_string_literal: true

class AiWorkflowNode < ApplicationRecord
  # Authentication & Authorization
  belongs_to :ai_workflow

  # Associations
  has_many :ai_workflow_node_executions, dependent: :destroy
  has_many :source_edges, class_name: "AiWorkflowEdge",
           foreign_key: "source_node_id", primary_key: "node_id", dependent: :destroy
  has_many :target_edges, class_name: "AiWorkflowEdge",
           foreign_key: "target_node_id", primary_key: "node_id", dependent: :destroy

  # Validations
  validates :node_id, presence: true, uniqueness: { scope: :ai_workflow_id }
  # Consolidated node types (24 total):
  # - Core: start, end, trigger
  # - AI/Processing: ai_agent, prompt_template, data_processor, transform
  # - Flow control: condition, loop, delay, merge, split
  # - Data: database, file, validator
  # - Communication: email, notification, api_call, webhook, scheduler
  # - Advanced: human_approval, sub_workflow
  # - Consolidated: kb_article (action: create|read|update|search|publish)
  #                 page (action: create|read|update|publish)
  #                 mcp_operation (operation_type: tool|resource|prompt)
  VALID_NODE_TYPES = %w[
    start end trigger
    ai_agent prompt_template data_processor transform
    condition loop delay merge split
    database file validator
    email notification
    api_call webhook scheduler
    human_approval sub_workflow
    kb_article page mcp_operation
  ].freeze

  # Valid actions for consolidated node types
  KB_ARTICLE_ACTIONS = %w[create read update search publish].freeze
  PAGE_ACTIONS = %w[create read update publish].freeze
  MCP_OPERATION_TYPES = %w[tool resource prompt].freeze

  validates :node_type, presence: true, inclusion: {
    in: VALID_NODE_TYPES,
    message: "must be a valid node type"
  }
  validate :validate_consolidated_node_action
  validates :name, presence: true, length: { maximum: 255 }
  validates :position, presence: true
  validates :configuration, presence: true, unless: :configuration_optional_for_type?
  validates :timeout_seconds, numericality: { greater_than: 0 }
  validates :retry_count, numericality: { greater_than_or_equal_to: 0 }
  validate :validate_node_configuration
  # Note: Start/end node uniqueness is validated at the workflow level, not per-node
  # This prevents timing issues during bulk updates while maintaining the constraint

  # JSON columns
  attribute :position, :json, default: -> { { x: 0, y: 0 } }
  attribute :configuration, :json, default: -> { {} }
  attribute :validation_rules, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  # Scopes
  scope :start_nodes, -> { where(is_start_node: true) }
  scope :end_nodes, -> { where(is_end_node: true) }
  scope :error_handlers, -> { where(is_error_handler: true) }
  scope :by_type, ->(type) { where(node_type: type) }
  scope :ordered_by_position, -> { order(:created_at) }

  # Callbacks
  before_validation :set_default_configuration
  after_create :update_workflow_metadata
  after_destroy :update_workflow_metadata

  # Node type check methods
  def ai_agent_node?
    node_type == "ai_agent"
  end

  def api_call_node?
    node_type == "api_call"
  end

  def webhook_node?
    node_type == "webhook"
  end

  def condition_node?
    node_type == "condition"
  end

  def loop_node?
    node_type == "loop"
  end

  def transform_node?
    node_type == "transform"
  end

  def delay_node?
    node_type == "delay"
  end

  def human_approval_node?
    node_type == "human_approval"
  end

  def sub_workflow_node?
    node_type == "sub_workflow"
  end

  def merge_node?
    node_type == "merge"
  end

  def split_node?
    node_type == "split"
  end

  # Consolidated node type check methods
  def kb_article_node?
    node_type == "kb_article"
  end

  def page_node?
    node_type == "page"
  end

  def mcp_operation_node?
    node_type == "mcp_operation"
  end

  # Action/operation type helpers for consolidated nodes
  def kb_article_action
    return nil unless kb_article_node?

    configuration["action"]
  end

  def page_action
    return nil unless page_node?

    configuration["action"]
  end

  def mcp_operation_type
    return nil unless mcp_operation_node?

    configuration["operation_type"]
  end

  def start_node?
    node_type == "start"
  end

  def end_node?
    node_type == "end"
  end

  def trigger_node?
    node_type == "trigger"
  end

  # Execution methods
  def can_execute?
    configuration.present? && valid_configuration_for_type?
  end

  def next_nodes
    source_edges.includes(:target_node).map(&:target_node)
  end

  def previous_nodes
    target_edges.includes(:source_node).map(&:source_node)
  end

  def has_conditions?
    source_edges.where(is_conditional: true).any?
  end

  def error_handler_node
    return nil unless error_node_id.present?

    ai_workflow.ai_workflow_nodes.find_by(node_id: error_node_id)
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

  # Node execution summary
  def execution_summary(days = 30)
    executions = ai_workflow_node_executions.where("created_at >= ?", days.days.ago)

    {
      total_executions: executions.count,
      successful_executions: executions.where(status: "completed").count,
      failed_executions: executions.where(status: "failed").count,
      average_duration: executions.where(status: "completed").average(:duration_ms)&.to_i || 0,
      total_cost: executions.sum(:cost),
      last_execution: executions.order(created_at: :desc).first&.created_at
    }
  end

  # Node positioning and layout
  def update_position(x, y)
    update!(position: position.merge({ x: x, y: y }))
  end

  def distance_to(other_node)
    return Float::INFINITY unless other_node.is_a?(AiWorkflowNode)

    dx = position["x"] - other_node.position["x"]
    dy = position["y"] - other_node.position["y"]
    Math.sqrt(dx * dx + dy * dy)
  end

  # Configuration management
  def update_configuration(new_config)
    merged_config = configuration.deep_merge(new_config)
    update!(configuration: merged_config)
  end

  def reset_configuration
    update!(configuration: default_configuration_for_type)
  end

  private

  def set_default_configuration
    return if configuration.present?

    self.configuration = default_configuration_for_type
  end

  def default_configuration_for_type
    case node_type
    when "ai_agent"
      {
        "agent_id" => nil,
        # prompt_template intentionally omitted - user will provide it
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
    when "api_call"
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
    when "webhook"
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
    when "condition"
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
    when "loop"
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
    when "transform"
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
    when "delay"
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
    when "human_approval"
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
    when "sub_workflow"
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
    when "merge"
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
    when "split"
      {
        "split_strategy" => "parallel",
        "branches" => [],
        "condition_variable" => "input",
        "output_mapping" => {
          "output" => "input",
          "data" => "data"
        }
      }
    when "start"
      {
        "start_type" => "manual",
        "delay_seconds" => 0,
        "output_mapping" => {
          "output" => "start_data",
          "data" => "start_data"
        }
      }
    when "end"
      {
        "end_type" => "success",
        "success_message" => "",
        "failure_message" => "",
        "artifacts" => []
      }
    when "trigger"
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
    when "kb_article"
      # Consolidated KB article node with action parameter
      {
        "action" => "create", # create, read, update, search, publish
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
    when "page"
      # Consolidated Page node with action parameter
      {
        "action" => "create", # create, read, update, publish
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
    when "mcp_operation"
      # Consolidated MCP node with operation_type parameter
      {
        "operation_type" => "tool", # tool, resource, prompt
        "mcp_server_id" => nil,
        "mcp_server_name" => nil,
        # Tool-specific fields
        "mcp_tool_id" => nil,
        "mcp_tool_name" => nil,
        "execution_mode" => "sync",
        "parameters" => {},
        "parameter_mappings" => [],
        # Resource-specific fields
        "resource_uri" => "",
        # Prompt-specific fields
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
    else
      {}
    end
  end

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
    end
  end

  def validate_consolidated_node_action
    case node_type
    when "kb_article"
      action = configuration["action"]
      unless KB_ARTICLE_ACTIONS.include?(action)
        errors.add(:configuration, "action must be one of: #{KB_ARTICLE_ACTIONS.join(', ')}")
      end
    when "page"
      action = configuration["action"]
      unless PAGE_ACTIONS.include?(action)
        errors.add(:configuration, "action must be one of: #{PAGE_ACTIONS.join(', ')}")
      end
    when "mcp_operation"
      operation_type = configuration["operation_type"]
      unless MCP_OPERATION_TYPES.include?(operation_type)
        errors.add(:configuration, "operation_type must be one of: #{MCP_OPERATION_TYPES.join(', ')}")
      end
    end
  end

  def validate_ai_agent_configuration
    if configuration["agent_id"].blank?
      errors.add(:configuration, "must specify an agent_id for AI agent nodes")
    elsif !ai_workflow.account.ai_agents.exists?(id: configuration["agent_id"])
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
    elsif !ai_workflow.account.ai_workflows.exists?(id: configuration["workflow_id"])
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
    elsif !ai_workflow.account.mcp_servers.exists?(id: configuration["mcp_server_id"])
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
      KB_ARTICLE_ACTIONS.include?(configuration["action"])
    when "page"
      PAGE_ACTIONS.include?(configuration["action"])
    when "mcp_operation"
      MCP_OPERATION_TYPES.include?(configuration["operation_type"]) &&
        configuration["mcp_server_id"].present?
    else
      true
    end
  end

  def update_workflow_metadata
    ai_workflow.touch(:updated_at)
  end

  def configuration_optional_for_type?
    # No node types have optional configuration anymore
    # All nodes should have proper configuration
    false
  end
end
