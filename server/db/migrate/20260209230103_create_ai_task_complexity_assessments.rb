# frozen_string_literal: true

class CreateAiTaskComplexityAssessments < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_task_complexity_assessments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :routing_decision, type: :uuid, null: true, foreign_key: { to_table: :ai_routing_decisions }, index: true
      t.string :task_type, null: false
      t.integer :input_token_count, default: 0
      t.integer :tool_count, default: 0
      t.integer :conversation_depth, default: 0
      t.jsonb :complexity_signals, default: {}
      t.decimal :complexity_score, precision: 5, scale: 4, null: false
      t.string :complexity_level, null: false
      t.string :recommended_tier, null: false
      t.string :actual_tier_used
      t.string :classifier_version, null: false

      t.timestamps
    end

    add_check_constraint :ai_task_complexity_assessments,
      "complexity_level IN ('trivial', 'simple', 'moderate', 'complex', 'expert')",
      name: "chk_ai_task_complexity_level"

    add_check_constraint :ai_task_complexity_assessments,
      "recommended_tier IN ('economy', 'standard', 'premium')",
      name: "chk_ai_task_recommended_tier"

    add_index :ai_task_complexity_assessments, :task_type
    add_index :ai_task_complexity_assessments, :complexity_level
    add_index :ai_task_complexity_assessments, :recommended_tier
  end
end
