# frozen_string_literal: true

class DropAiWorkflowsSystem < ActiveRecord::Migration[8.0]
  def up
    # Phase 1A: Remove FK columns from surviving tables
    # Must happen before dropping referenced tables

    if column_exists?(:ai_a2a_tasks, :ai_workflow_run_id)
      remove_column :ai_a2a_tasks, :ai_workflow_run_id
    end

    if column_exists?(:ai_pipeline_executions, :workflow_run_id)
      remove_column :ai_pipeline_executions, :workflow_run_id
    end

    if column_exists?(:ai_routing_decisions, :workflow_run_id)
      remove_column :ai_routing_decisions, :workflow_run_id
    end

    if column_exists?(:ai_recorded_interactions, :source_workflow_run_id)
      remove_column :ai_recorded_interactions, :source_workflow_run_id
    end

    if column_exists?(:ai_dag_executions, :workflow_id)
      remove_column :ai_dag_executions, :workflow_id
    end

    if column_exists?(:ai_trajectories, :workflow_run_id)
      remove_column :ai_trajectories, :workflow_run_id
    end

    if column_exists?(:ai_performance_benchmarks, :target_workflow_id)
      remove_column :ai_performance_benchmarks, :target_workflow_id
    end

    if column_exists?(:ai_test_scenarios, :target_workflow_id)
      remove_column :ai_test_scenarios, :target_workflow_id
    end

    if column_exists?(:ai_devops_template_installations, :created_workflow_id)
      remove_column :ai_devops_template_installations, :created_workflow_id
    end

    # Remove FK constraints from tables that reference workflow tables
    if column_exists?(:supply_chain_remediation_plans, :workflow_run_id)
      remove_column :supply_chain_remediation_plans, :workflow_run_id
    elsif foreign_key_exists?(:supply_chain_remediation_plans, :ai_workflow_runs)
      remove_foreign_key :supply_chain_remediation_plans, :ai_workflow_runs
    end

    # Phase 1B: Drop workflow tables using CASCADE to handle remaining FK constraints
    tables_to_drop = %i[
      ai_workflow_approval_tokens
      ai_workflow_compensations
      ai_workflow_checkpoints
      ai_workflow_run_logs
      ai_workflow_node_executions
      ai_shared_context_pools
      batch_workflow_runs
      git_workflow_triggers
      ai_workflow_runs
      ai_workflow_edges
      ai_workflow_variables
      ai_workflow_triggers
      ai_workflow_schedules
      ai_workflow_nodes
      ai_workflow_templates
      ai_workflow_template_installations
      workflow_validations
      ai_workflow_executions
      ai_workflows
    ]

    tables_to_drop.each do |table|
      if table_exists?(table)
        execute "DROP TABLE #{table} CASCADE"
      end
    end

    # Phase 1C: Update agents with removed agent_types
    execute <<-SQL
      UPDATE ai_agents
      SET agent_type = 'assistant'
      WHERE agent_type IN ('workflow_optimizer', 'workflow_operations')
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "AI Workflows system has been permanently removed"
  end
end
