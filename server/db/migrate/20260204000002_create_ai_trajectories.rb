# frozen_string_literal: true

class CreateAiTrajectories < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_trajectories, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :ai_agent, foreign_key: true, type: :uuid, index: true
      t.uuid :team_execution_id
      t.uuid :workflow_run_id
      t.string :trajectory_id, null: false
      t.string :title, null: false
      t.text :summary
      t.string :status, null: false, default: "building"
      t.string :trajectory_type, null: false
      t.float :quality_score
      t.integer :access_count, default: 0
      t.integer :chapter_count, default: 0
      t.jsonb :tags, default: []
      t.jsonb :outcome_summary, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :ai_trajectories, :trajectory_id, unique: true
    add_index :ai_trajectories, :status
    add_index :ai_trajectories, :tags, using: :gin
    add_index :ai_trajectories, :team_execution_id
    add_index :ai_trajectories, :workflow_run_id

    create_table :ai_trajectory_chapters, id: :uuid do |t|
      t.references :trajectory, null: false, foreign_key: { to_table: :ai_trajectories }, type: :uuid, index: true
      t.integer :chapter_number, null: false
      t.string :title, null: false
      t.string :chapter_type, null: false
      t.text :content, null: false
      t.text :reasoning
      t.jsonb :key_decisions, default: []
      t.jsonb :artifacts, default: []
      t.jsonb :context_references, default: []
      t.integer :duration_ms
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :ai_trajectory_chapters, [:trajectory_id, :chapter_number], unique: true, name: "idx_trajectory_chapters_on_trajectory_and_number"
    add_index :ai_trajectory_chapters, :chapter_type
  end
end
