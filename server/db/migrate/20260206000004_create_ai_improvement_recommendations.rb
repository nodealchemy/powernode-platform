# frozen_string_literal: true

class CreateAiImprovementRecommendations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_improvement_recommendations, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.string :recommendation_type, null: false
      t.string :target_type, null: false
      t.uuid :target_id, null: false
      t.jsonb :current_config, default: {}
      t.jsonb :recommended_config, default: {}
      t.jsonb :evidence, default: {}
      t.decimal :confidence_score, precision: 5, scale: 4, null: false
      t.string :status, null: false, default: "pending"
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :users }, index: true, null: true
      t.datetime :applied_at

      t.timestamps
    end

    add_index :ai_improvement_recommendations, [:target_type, :target_id]
    add_index :ai_improvement_recommendations, :status
    add_index :ai_improvement_recommendations, :recommendation_type
  end
end
