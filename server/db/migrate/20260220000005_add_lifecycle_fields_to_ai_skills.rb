# frozen_string_literal: true

class AddLifecycleFieldsToAiSkills < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_skills, :parent_skill, type: :uuid,
                  foreign_key: { to_table: :ai_skills }, null: true
    add_column :ai_skills, :effectiveness_score, :decimal, precision: 5, scale: 4, default: "0.5"
    add_column :ai_skills, :positive_usage_count, :integer, default: 0
    add_column :ai_skills, :negative_usage_count, :integer, default: 0
    add_column :ai_skills, :last_used_at, :datetime
    add_column :ai_skills, :last_optimized_at, :datetime
    add_column :ai_skills, :lifecycle_metadata, :jsonb, default: {}
  end
end
