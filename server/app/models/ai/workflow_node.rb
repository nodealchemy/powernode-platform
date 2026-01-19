# frozen_string_literal: true

module Ai
  class WorkflowNode < ApplicationRecord
    # Extracted concerns
    include Ai::WorkflowNode::NodeTypes
    include Ai::WorkflowNode::Connections
    include Ai::WorkflowNode::ConfigurationHelpers
    include Ai::WorkflowNode::Validation
    include Ai::WorkflowNode::Statistics
    include Ai::WorkflowNode::Positioning

    # Associations
    belongs_to :workflow, class_name: "Ai::Workflow", foreign_key: "ai_workflow_id"
    has_many :node_executions, class_name: "Ai::WorkflowNodeExecution", foreign_key: "ai_workflow_node_id", dependent: :destroy

    has_many :source_edges, class_name: "Ai::WorkflowEdge",
             foreign_key: "source_node_id", primary_key: "node_id", dependent: :destroy
    has_many :target_edges, class_name: "Ai::WorkflowEdge",
             foreign_key: "target_node_id", primary_key: "node_id", dependent: :destroy

    # Consolidated node types (38 total - includes CI/CD and integrations)
    VALID_NODE_TYPES = %w[
      start end trigger
      ai_agent prompt_template data_processor transform
      condition loop delay merge split
      database file validator
      email notification
      api_call webhook scheduler
      human_approval sub_workflow
      kb_article page mcp_operation
      ci_trigger ci_wait_status ci_get_logs ci_cancel
      git_commit_status git_create_check
      integration_execute
      git_checkout git_branch git_pull_request git_comment
      deploy run_tests shell_command
    ].freeze

    # CI/CD node type constants
    CI_TRIGGER_ACTIONS = %w[workflow_dispatch repository_dispatch create_run].freeze
    CI_WAIT_STATUS_OPTIONS = %w[success failure completed any].freeze
    GIT_COMMIT_STATUS_STATES = %w[pending success failure error].freeze

    # Valid actions for consolidated node types
    KB_ARTICLE_ACTIONS = %w[create read update search publish].freeze
    PAGE_ACTIONS = %w[create read update publish].freeze
    MCP_OPERATION_TYPES = %w[tool resource prompt].freeze

    # Validations
    validates :node_id, presence: true, uniqueness: { scope: :ai_workflow_id }
    validates :node_type, presence: true, inclusion: {
      in: VALID_NODE_TYPES,
      message: "must be a valid node type"
    }
    validates :name, presence: true, length: { maximum: 255 }
    validates :position, presence: true
    validates :configuration, presence: true, unless: :configuration_optional_for_type?
    validates :timeout_seconds, numericality: { greater_than: 0 }
    validates :retry_count, numericality: { greater_than_or_equal_to: 0 }

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
    after_create :update_workflow_metadata
    after_destroy :update_workflow_metadata

    private

    def update_workflow_metadata
      workflow.touch(:updated_at)
    end

    def configuration_optional_for_type?
      false
    end
  end
end
