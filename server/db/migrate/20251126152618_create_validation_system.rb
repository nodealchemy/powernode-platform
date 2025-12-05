# frozen_string_literal: true

class CreateValidationSystem < ActiveRecord::Migration[7.1]
  def change
    create_table :validation_rules, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :category, null: false
      t.string :severity, null: false, default: 'warning'
      t.boolean :enabled, default: true
      t.boolean :auto_fixable, default: false
      t.jsonb :configuration, default: {}
      t.timestamps

      t.index [:category, :enabled]
      t.index :severity
    end

    create_table :workflow_validations, id: :uuid do |t|
      t.references :workflow, type: :uuid, null: false, foreign_key: { to_table: :ai_workflows }
      t.string :overall_status, null: false
      t.integer :health_score, null: false
      t.integer :total_nodes, null: false
      t.integer :validated_nodes, null: false
      t.jsonb :issues, null: false, default: []
      t.integer :validation_duration_ms
      t.timestamps

      t.index [:workflow_id, :created_at]
    end
  end
end
