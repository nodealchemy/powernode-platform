# frozen_string_literal: true

class CreateAiEvaluationResults < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_evaluation_results, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }, index: true
      t.uuid :execution_id, null: false
      t.string :evaluator_model, null: false
      t.jsonb :scores, default: {}
      t.text :feedback

      t.timestamps
    end

    add_index :ai_evaluation_results, :execution_id
    add_index :ai_evaluation_results, [:agent_id, :created_at]
  end
end
