# frozen_string_literal: true

class CreateAiTaskReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_task_reviews, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :team_task, null: false, foreign_key: { to_table: :ai_team_tasks }, type: :uuid, index: true
      t.references :reviewer_role, foreign_key: { to_table: :ai_team_roles }, type: :uuid, index: true
      t.references :reviewer_agent, foreign_key: { to_table: :ai_agents }, type: :uuid, index: true
      t.string :review_id, null: false
      t.string :status, null: false, default: "pending"
      t.string :review_mode, null: false, default: "blocking"
      t.float :quality_score
      t.jsonb :findings, default: []
      t.jsonb :completeness_checks, default: {}
      t.text :approval_notes
      t.text :rejection_reason
      t.integer :review_duration_ms
      t.integer :revision_count, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :ai_task_reviews, :review_id, unique: true
    add_index :ai_task_reviews, [:team_task_id, :status], name: "idx_task_reviews_on_task_and_status"

    add_column :ai_agent_teams, :review_config, :jsonb, default: {}
  end
end
