# frozen_string_literal: true

# Migration to add CI/CD node types to the workflow nodes check constraint.
# This enables AI workflows to interact with CI/CD pipelines:
# - ci_trigger: Trigger GitHub Actions/GitLab CI workflows
# - ci_wait_status: Wait for pipeline to complete
# - ci_get_logs: Fetch pipeline logs
# - ci_cancel: Cancel running pipeline
# - git_commit_status: Set commit status (pending/success/failure)
# - git_create_check: Create GitHub check run
class AddCiCdNodeTypes < ActiveRecord::Migration[8.0]
  def up
    # Remove old CHECK constraint
    remove_check_constraint :ai_workflow_nodes, name: 'ai_workflow_nodes_type_check'

    # Add new CHECK constraint with CI/CD node types (30 total)
    add_check_constraint :ai_workflow_nodes,
      build_node_type_constraint(all_node_types),
      name: 'ai_workflow_nodes_type_check'
  end

  def down
    # Remove CI/CD CHECK constraint
    remove_check_constraint :ai_workflow_nodes, name: 'ai_workflow_nodes_type_check'

    # Restore previous CHECK constraint (without CI/CD types)
    add_check_constraint :ai_workflow_nodes,
      build_node_type_constraint(previous_node_types),
      name: 'ai_workflow_nodes_type_check'
  end

  private

  def build_node_type_constraint(types)
    type_array = types.map { |t| "'#{t}'::character varying::text" }.join(', ')
    "node_type::text = ANY (ARRAY[#{type_array}])"
  end

  def all_node_types
    %w[
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
    ]
  end

  def previous_node_types
    %w[
      start end trigger
      ai_agent prompt_template data_processor transform
      condition loop delay merge split
      database file validator
      email notification
      api_call webhook scheduler
      human_approval sub_workflow
      kb_article page mcp_operation
    ]
  end
end
