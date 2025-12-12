# frozen_string_literal: true

class CreateAiWorkflowVariables < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_variables, id: :uuid do |t|
      t.references :ai_workflow, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false, limit: 100
      t.string :variable_type, null: false, default: 'string'
      t.text :description
      t.jsonb :default_value
      t.jsonb :validation_rules, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.boolean :is_required, null: false, default: false
      t.boolean :is_input, null: false, default: false
      t.boolean :is_output, null: false, default: false
      t.boolean :is_secret, null: false, default: false
      t.string :scope, null: false, default: 'workflow'
      t.timestamps

      t.index [ :ai_workflow_id, :name ], unique: true, name: 'index_workflow_variables_on_workflow_name'
      t.index [ :ai_workflow_id, :is_input ]
      t.index [ :ai_workflow_id, :is_output ]
      t.index [ :ai_workflow_id, :is_required ]
      t.index :scope
    end

    add_check_constraint :ai_workflow_variables,
      "variable_type IN ('string', 'number', 'boolean', 'object', 'array', 'date', 'datetime', 'file', 'json')",
      name: 'ai_workflow_variables_type_check'

    add_check_constraint :ai_workflow_variables,
      "scope IN ('workflow', 'node', 'global')",
      name: 'ai_workflow_variables_scope_check'

    add_check_constraint :ai_workflow_variables,
      "name ~ '^[a-zA-Z][a-zA-Z0-9_]*$'",
      name: 'ai_workflow_variables_name_format_check'
  end
end
