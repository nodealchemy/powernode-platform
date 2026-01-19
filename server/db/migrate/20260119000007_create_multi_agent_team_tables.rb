# frozen_string_literal: true

# Multi-Agent Team Tables - CrewAI-Style Orchestration
#
# Revenue Model: Tiered subscriptions + agent seat pricing
# - Starter: 3 agents, 1 team ($49/mo)
# - Pro: 10 agents, 5 teams, advanced patterns ($199/mo)
# - Enterprise: Unlimited + custom topologies ($999/mo)
# - Per-agent-seat pricing for large deployments ($15/agent/mo)
#
class CreateMultiAgentTeamTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # TEAM ROLES - Specialized roles within a team
    # ==========================================================================
    create_table :ai_team_roles, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :agent_team, null: false, foreign_key: { to_table: :ai_agent_teams }, type: :uuid
      t.references :ai_agent, foreign_key: true, type: :uuid
      t.string :role_name, null: false
      t.string :role_type, null: false, default: "worker"
      t.text :role_description
      t.text :responsibilities
      t.text :goals
      t.jsonb :capabilities, default: []
      t.jsonb :constraints, default: []
      t.jsonb :tools_allowed, default: []
      t.integer :priority_order, default: 0
      t.boolean :can_delegate, null: false, default: false
      t.boolean :can_escalate, null: false, default: true
      t.integer :max_concurrent_tasks, default: 1
      t.jsonb :context_access, default: {}
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_team_roles, [:agent_team_id, :role_name], unique: true
    add_index :ai_team_roles, [:agent_team_id, :priority_order]
    add_index :ai_team_roles, :role_type

    # ==========================================================================
    # TEAM COMMUNICATION CHANNELS - Inter-agent communication
    # ==========================================================================
    create_table :ai_team_channels, id: :uuid do |t|
      t.references :agent_team, null: false, foreign_key: { to_table: :ai_agent_teams }, type: :uuid
      t.string :name, null: false
      t.string :channel_type, null: false, default: "broadcast"
      t.text :description
      t.jsonb :participant_roles, default: []
      t.jsonb :message_schema, default: {}
      t.boolean :is_persistent, null: false, default: true
      t.integer :message_retention_hours
      t.jsonb :routing_rules, default: {}
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_team_channels, [:agent_team_id, :name], unique: true
    add_index :ai_team_channels, :channel_type

    # ==========================================================================
    # TEAM EXECUTIONS - Team-level execution tracking
    # ==========================================================================
    create_table :ai_team_executions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :agent_team, null: false, foreign_key: { to_table: :ai_agent_teams }, type: :uuid
      t.references :triggered_by, foreign_key: { to_table: :users }, type: :uuid
      t.uuid :workflow_run_id
      t.string :execution_id, null: false
      t.string :status, null: false, default: "pending"
      t.text :objective
      t.jsonb :input_context, default: {}
      t.jsonb :output_result, default: {}
      t.jsonb :shared_memory, default: {}
      t.integer :tasks_total, default: 0
      t.integer :tasks_completed, default: 0
      t.integer :tasks_failed, default: 0
      t.integer :messages_exchanged, default: 0
      t.integer :total_tokens_used, default: 0
      t.decimal :total_cost_usd, precision: 10, scale: 4, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.string :termination_reason
      t.jsonb :performance_metrics, default: {}
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_team_executions, :execution_id, unique: true
    add_index :ai_team_executions, [:account_id, :status]
    add_index :ai_team_executions, [:agent_team_id, :created_at]
    add_index :ai_team_executions, :started_at

    # ==========================================================================
    # TEAM TASKS - Individual tasks within a team execution
    # ==========================================================================
    create_table :ai_team_tasks, id: :uuid do |t|
      t.references :team_execution, null: false, foreign_key: { to_table: :ai_team_executions }, type: :uuid
      t.references :assigned_role, foreign_key: { to_table: :ai_team_roles }, type: :uuid
      t.references :assigned_agent, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.uuid :parent_task_id
      t.uuid :delegated_from_task_id
      t.string :task_id, null: false
      t.string :task_type, null: false, default: "execution"
      t.string :status, null: false, default: "pending"
      t.text :description, null: false
      t.text :expected_output
      t.jsonb :input_data, default: {}
      t.jsonb :output_data, default: {}
      t.jsonb :tools_used, default: []
      t.integer :priority, default: 5
      t.integer :retry_count, default: 0
      t.integer :max_retries, default: 3
      t.integer :tokens_used, default: 0
      t.decimal :cost_usd, precision: 10, scale: 4, default: 0
      t.datetime :assigned_at
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.string :failure_reason
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_team_tasks, :task_id, unique: true
    add_index :ai_team_tasks, [:team_execution_id, :status]
    add_index :ai_team_tasks, [:assigned_role_id, :status]
    add_index :ai_team_tasks, :parent_task_id
    add_index :ai_team_tasks, :priority

    # ==========================================================================
    # TEAM MESSAGES - Inter-agent messages
    # ==========================================================================
    create_table :ai_team_messages, id: :uuid do |t|
      t.references :team_execution, null: false, foreign_key: { to_table: :ai_team_executions }, type: :uuid
      t.references :channel, foreign_key: { to_table: :ai_team_channels }, type: :uuid
      t.references :from_role, foreign_key: { to_table: :ai_team_roles }, type: :uuid
      t.references :to_role, foreign_key: { to_table: :ai_team_roles }, type: :uuid
      t.uuid :in_reply_to_id
      t.uuid :task_id
      t.string :message_type, null: false, default: "task_update"
      t.text :content, null: false
      t.jsonb :structured_content, default: {}
      t.jsonb :attachments, default: []
      t.integer :sequence_number
      t.string :priority, default: "normal"
      t.boolean :requires_response, null: false, default: false
      t.datetime :read_at
      t.datetime :responded_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_team_messages, [:team_execution_id, :sequence_number]
    add_index :ai_team_messages, [:channel_id, :created_at]
    add_index :ai_team_messages, [:from_role_id, :created_at]
    add_index :ai_team_messages, :message_type
    add_index :ai_team_messages, :in_reply_to_id

    # ==========================================================================
    # TEAM TEMPLATES - Pre-built team configurations
    # ==========================================================================
    create_table :ai_team_templates, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :category
      t.string :team_topology, null: false, default: "hierarchical"
      t.jsonb :role_definitions, default: []
      t.jsonb :channel_definitions, default: []
      t.jsonb :workflow_pattern, default: {}
      t.jsonb :default_config, default: {}
      t.boolean :is_system, null: false, default: false
      t.boolean :is_public, null: false, default: false
      t.integer :usage_count, default: 0
      t.float :average_rating
      t.jsonb :tags, default: []
      t.datetime :published_at

      t.timestamps
    end

    add_index :ai_team_templates, :slug, unique: true
    add_index :ai_team_templates, [:is_public, :category]
    add_index :ai_team_templates, :team_topology
    add_index :ai_team_templates, :is_system

    # ==========================================================================
    # ADD COLUMNS TO EXISTING TABLES
    # ==========================================================================

    # Enhance ai_agent_teams with orchestration fields
    # Note: coordination_strategy already exists from initial table creation
    add_column :ai_agent_teams, :team_topology, :string, default: "hierarchical"
    add_column :ai_agent_teams, :communication_pattern, :string, default: "hub_spoke"
    add_column :ai_agent_teams, :max_parallel_tasks, :integer, default: 3
    add_column :ai_agent_teams, :task_timeout_seconds, :integer, default: 300
    add_column :ai_agent_teams, :escalation_policy, :jsonb, default: {}
    add_column :ai_agent_teams, :shared_memory_config, :jsonb, default: {}
    add_column :ai_agent_teams, :human_checkpoint_config, :jsonb, default: {}
    add_column :ai_agent_teams, :template_id, :uuid

    add_index :ai_agent_teams, :team_topology
    add_index :ai_agent_teams, :template_id

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE ai_team_roles
      ADD CONSTRAINT check_team_role_type
      CHECK (role_type IN ('manager', 'coordinator', 'worker', 'specialist', 'reviewer', 'validator'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_team_channels
      ADD CONSTRAINT check_channel_type
      CHECK (channel_type IN ('broadcast', 'direct', 'topic', 'task', 'escalation'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_team_executions
      ADD CONSTRAINT check_team_execution_status
      CHECK (status IN ('pending', 'running', 'paused', 'completed', 'failed', 'cancelled', 'timeout'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_team_tasks
      ADD CONSTRAINT check_team_task_status
      CHECK (status IN ('pending', 'assigned', 'in_progress', 'waiting', 'completed', 'failed', 'cancelled', 'delegated'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_team_tasks
      ADD CONSTRAINT check_team_task_type
      CHECK (task_type IN ('execution', 'review', 'validation', 'coordination', 'escalation', 'human_input'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_team_messages
      ADD CONSTRAINT check_team_message_type
      CHECK (message_type IN ('task_assignment', 'task_update', 'task_result', 'question', 'answer', 'escalation', 'coordination', 'broadcast', 'human_input'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_team_templates
      ADD CONSTRAINT check_team_topology
      CHECK (team_topology IN ('hierarchical', 'flat', 'mesh', 'pipeline', 'hybrid'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_agent_teams
      ADD CONSTRAINT check_team_topology_enum
      CHECK (team_topology IN ('hierarchical', 'flat', 'mesh', 'pipeline', 'hybrid'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_agent_teams
      ADD CONSTRAINT check_communication_pattern
      CHECK (communication_pattern IN ('hub_spoke', 'peer_to_peer', 'broadcast', 'sequential', 'event_driven'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_agent_teams
      ADD CONSTRAINT check_coordination_strategy
      CHECK (coordination_strategy IN ('manager_led', 'consensus', 'auction', 'round_robin', 'priority_based'))
    SQL
  end
end
