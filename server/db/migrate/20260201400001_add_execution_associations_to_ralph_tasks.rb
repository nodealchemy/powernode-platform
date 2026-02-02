# frozen_string_literal: true

class AddExecutionAssociationsToRalphTasks < ActiveRecord::Migration[8.0]
  def change
    # ===========================================================================
    # Ralph Task Execution Associations
    # ===========================================================================
    # Adds polymorphic executor support to Ralph Tasks enabling tasks to be
    # executed by various executor types: AI Agents, Workflows, DevOps Pipelines,
    # A2A Tasks, Containers, Human Review queues, or Community Agents.
    # ===========================================================================

    # Execution type enumeration
    # Determines which type of executor will handle this task
    add_column :ai_ralph_tasks, :execution_type, :string, default: "agent"

    # Polymorphic executor association
    # Links to the actual executor instance (Agent, Workflow, Pipeline, etc.)
    add_reference :ai_ralph_tasks, :executor, polymorphic: true, type: :uuid

    # Capability-based routing
    # required_capabilities: Array of skill/capability names the executor must have
    # capability_match_strategy: How to match capabilities (all, any, weighted)
    add_column :ai_ralph_tasks, :required_capabilities, :jsonb, default: []
    add_column :ai_ralph_tasks, :capability_match_strategy, :string, default: "all"

    # Delegation configuration
    # Controls how task delegation works (allowed agents, timeout, retry, fallback)
    # Schema: {
    #   allowed_agents: ["agent-uuid-1", "agent-uuid-2"],
    #   max_delegation_depth: 3,
    #   allow_sub_delegation: true,
    #   timeout_seconds: 3600,
    #   retry_strategy: "exponential",
    #   fallback_executor_type: "human",
    #   fallback_executor_id: "user-uuid"
    # }
    add_column :ai_ralph_tasks, :delegation_config, :jsonb, default: {}

    # Execution tracking
    # execution_attempts: Number of times execution has been attempted
    # last_executor: Tracks the last executor used (for retry/fallback scenarios)
    add_column :ai_ralph_tasks, :execution_attempts, :integer, default: 0
    add_reference :ai_ralph_tasks, :last_executor, polymorphic: true, type: :uuid

    # Indexes for efficient querying
    add_index :ai_ralph_tasks, :execution_type
    add_index :ai_ralph_tasks, [:executor_type, :executor_id]
    add_index :ai_ralph_tasks, :required_capabilities, using: :gin
    add_index :ai_ralph_tasks, :capability_match_strategy

    # Constraint for valid execution types
    add_check_constraint :ai_ralph_tasks,
      "execution_type IN ('agent', 'workflow', 'pipeline', 'a2a_task', 'container', 'human', 'community')",
      name: "ai_ralph_tasks_execution_type_check"

    # Constraint for valid capability match strategies
    add_check_constraint :ai_ralph_tasks,
      "capability_match_strategy IN ('all', 'any', 'weighted')",
      name: "ai_ralph_tasks_capability_match_strategy_check"
  end
end
