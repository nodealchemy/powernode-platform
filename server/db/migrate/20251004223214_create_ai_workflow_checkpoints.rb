# frozen_string_literal: true

class CreateAiWorkflowCheckpoints < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_workflow_checkpoints, id: :uuid do |t|
      t.uuid :ai_workflow_run_id, null: false
      t.string :checkpoint_id, null: false
      t.string :node_id, null: false
      t.string :checkpoint_type, null: false, default: 'node_completion'
      t.integer :sequence_number, null: false
      t.jsonb :workflow_state, null: false, default: {}
      t.jsonb :execution_context, null: false, default: {}
      t.jsonb :variable_snapshot, default: {}
      t.jsonb :metadata, default: {}
      t.text :description

      t.timestamps
    end

    add_index :ai_workflow_checkpoints, :ai_workflow_run_id
    add_index :ai_workflow_checkpoints, :checkpoint_id
    add_index :ai_workflow_checkpoints, :sequence_number
    add_foreign_key :ai_workflow_checkpoints, :ai_workflow_runs, on_delete: :cascade
    add_index :ai_workflow_checkpoints, [:ai_workflow_run_id, :sequence_number],
              name: 'index_checkpoints_on_run_and_sequence'
    add_index :ai_workflow_checkpoints, [:ai_workflow_run_id, :checkpoint_id],
              unique: true, name: 'index_checkpoints_on_run_and_id'
  end
end
