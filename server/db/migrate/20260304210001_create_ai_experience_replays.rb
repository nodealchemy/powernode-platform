# frozen_string_literal: true

class CreateAiExperienceReplays < ActiveRecord::Migration[8.0]
  def up
    create_table :ai_experience_replays, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :ai_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
      t.references :source_execution, type: :uuid, foreign_key: { to_table: :ai_agent_executions }
      t.references :source_trajectory, type: :uuid, foreign_key: { to_table: :ai_trajectories }

      t.string :task_type, limit: 100
      t.text :task_description
      t.text :compressed_example, null: false
      t.decimal :quality_score, precision: 5, scale: 4, default: 0.5, null: false
      t.decimal :effectiveness_score, precision: 5, scale: 4, default: 0.5, null: false
      t.integer :token_count, default: 0, null: false
      t.integer :injection_count, default: 0, null: false
      t.integer :positive_outcome_count, default: 0, null: false
      t.integer :negative_outcome_count, default: 0, null: false
      t.string :status, default: "active", null: false
      t.jsonb :metadata, default: {}
      t.jsonb :tags, default: []
      t.datetime :last_injected_at

      t.timestamps
    end

    execute "ALTER TABLE ai_experience_replays ADD COLUMN embedding vector(1536)"

    add_index :ai_experience_replays, [:account_id, :ai_agent_id], name: "idx_experience_replays_account_agent"
    add_index :ai_experience_replays, [:account_id, :status], name: "idx_experience_replays_account_status"
    add_index :ai_experience_replays, :quality_score
    add_index :ai_experience_replays, :effectiveness_score
    add_index :ai_experience_replays, :tags, using: :gin

    execute <<~SQL
      CREATE INDEX idx_experience_replays_embedding
      ON ai_experience_replays USING hnsw (embedding vector_cosine_ops);
    SQL
  end

  def down
    drop_table :ai_experience_replays
  end
end
