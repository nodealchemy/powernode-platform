# frozen_string_literal: true

class MoveContainersFromMcpToDevops < ActiveRecord::Migration[8.0]
  def up
    # Drop all foreign keys referencing the tables being renamed
    remove_foreign_key :ai_a2a_tasks, :mcp_container_instances, column: :container_instance_id, if_exists: true
    remove_foreign_key :ai_ralph_loops, :mcp_container_instances, column: :container_instance_id, if_exists: true
    remove_foreign_key :mcp_container_instances, :mcp_container_templates, column: :template_id, if_exists: true
    remove_foreign_key :mcp_container_instances, :accounts, column: :account_id, if_exists: true
    remove_foreign_key :mcp_container_instances, :users, column: :triggered_by_id, if_exists: true
    remove_foreign_key :mcp_container_instances, :ai_a2a_tasks, column: :a2a_task_id, if_exists: true
    remove_foreign_key :mcp_container_templates, :accounts, column: :account_id, if_exists: true
    remove_foreign_key :mcp_container_templates, :users, column: :created_by_id, if_exists: true
    remove_foreign_key :mcp_resource_quotas, :accounts, column: :account_id, if_exists: true
    remove_foreign_key :mcp_secret_references, :accounts, column: :account_id, if_exists: true
    remove_foreign_key :mcp_secret_references, :users, column: :created_by_id, if_exists: true

    # Rename tables
    rename_table :mcp_container_templates, :devops_container_templates
    rename_table :mcp_container_instances, :devops_container_instances
    rename_table :mcp_resource_quotas, :devops_resource_quotas
    rename_table :mcp_secret_references, :devops_secret_references

    # Re-add foreign keys with new table names
    add_foreign_key :ai_a2a_tasks, :devops_container_instances, column: :container_instance_id
    add_foreign_key :ai_ralph_loops, :devops_container_instances, column: :container_instance_id
    add_foreign_key :devops_container_instances, :devops_container_templates, column: :template_id
    add_foreign_key :devops_container_instances, :accounts, column: :account_id
    add_foreign_key :devops_container_instances, :users, column: :triggered_by_id
    add_foreign_key :devops_container_instances, :ai_a2a_tasks, column: :a2a_task_id
    add_foreign_key :devops_container_templates, :accounts, column: :account_id
    add_foreign_key :devops_container_templates, :users, column: :created_by_id
    add_foreign_key :devops_resource_quotas, :accounts, column: :account_id
    add_foreign_key :devops_secret_references, :accounts, column: :account_id
    add_foreign_key :devops_secret_references, :users, column: :created_by_id
  end

  def down
    # Drop foreign keys with new table names
    remove_foreign_key :ai_a2a_tasks, :devops_container_instances, column: :container_instance_id, if_exists: true
    remove_foreign_key :ai_ralph_loops, :devops_container_instances, column: :container_instance_id, if_exists: true
    remove_foreign_key :devops_container_instances, :devops_container_templates, column: :template_id, if_exists: true
    remove_foreign_key :devops_container_instances, :accounts, column: :account_id, if_exists: true
    remove_foreign_key :devops_container_instances, :users, column: :triggered_by_id, if_exists: true
    remove_foreign_key :devops_container_instances, :ai_a2a_tasks, column: :a2a_task_id, if_exists: true
    remove_foreign_key :devops_container_templates, :accounts, column: :account_id, if_exists: true
    remove_foreign_key :devops_container_templates, :users, column: :created_by_id, if_exists: true
    remove_foreign_key :devops_resource_quotas, :accounts, column: :account_id, if_exists: true
    remove_foreign_key :devops_secret_references, :accounts, column: :account_id, if_exists: true
    remove_foreign_key :devops_secret_references, :users, column: :created_by_id, if_exists: true

    # Rename tables back
    rename_table :devops_container_templates, :mcp_container_templates
    rename_table :devops_container_instances, :mcp_container_instances
    rename_table :devops_resource_quotas, :mcp_resource_quotas
    rename_table :devops_secret_references, :mcp_secret_references

    # Re-add foreign keys with original table names
    add_foreign_key :ai_a2a_tasks, :mcp_container_instances, column: :container_instance_id
    add_foreign_key :ai_ralph_loops, :mcp_container_instances, column: :container_instance_id
    add_foreign_key :mcp_container_instances, :mcp_container_templates, column: :template_id
    add_foreign_key :mcp_container_instances, :accounts, column: :account_id
    add_foreign_key :mcp_container_instances, :users, column: :triggered_by_id
    add_foreign_key :mcp_container_instances, :ai_a2a_tasks, column: :a2a_task_id
    add_foreign_key :mcp_container_templates, :accounts, column: :account_id
    add_foreign_key :mcp_container_templates, :users, column: :created_by_id
    add_foreign_key :mcp_resource_quotas, :accounts, column: :account_id
    add_foreign_key :mcp_secret_references, :accounts, column: :account_id
    add_foreign_key :mcp_secret_references, :users, column: :created_by_id
  end
end
