# frozen_string_literal: true

class AddSharedPromptTemplateReferences < ActiveRecord::Migration[8.0]
  def change
    # Add reference to ai_workflow_nodes
    add_column :ai_workflow_nodes, :shared_prompt_template_id, :uuid
    add_index :ai_workflow_nodes, :shared_prompt_template_id
    add_foreign_key :ai_workflow_nodes, :shared_prompt_templates, on_delete: :nullify

    # Add reference to ci_cd_pipeline_steps
    add_column :ci_cd_pipeline_steps, :shared_prompt_template_id, :uuid
    add_index :ci_cd_pipeline_steps, :shared_prompt_template_id
    add_foreign_key :ci_cd_pipeline_steps, :shared_prompt_templates, on_delete: :nullify
  end
end
