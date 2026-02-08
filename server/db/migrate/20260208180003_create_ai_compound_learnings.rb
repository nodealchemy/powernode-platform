# frozen_string_literal: true

class CreateAiCompoundLearnings < ActiveRecord::Migration[8.0]
  def up
    create_table :ai_compound_learnings, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :ai_agent_team, foreign_key: true, type: :uuid
      t.references :source_agent, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.references :source_execution, foreign_key: { to_table: :ai_team_executions }, type: :uuid

      # Core content
      t.string :category, null: false
      t.text :content, null: false
      t.string :title, limit: 255

      # Scoring
      t.decimal :importance_score, precision: 5, scale: 4, default: 0.5, null: false
      t.decimal :confidence_score, precision: 5, scale: 4, default: 0.5, null: false
      t.decimal :effectiveness_score, precision: 5, scale: 4
      t.decimal :decay_rate, precision: 5, scale: 4, default: 0.003

      # Lifecycle
      t.string :status, default: "active", null: false
      t.string :scope, default: "team", null: false

      # Provenance
      t.boolean :source_execution_successful
      t.string :extraction_method

      # Injection tracking
      t.integer :injection_count, default: 0, null: false
      t.integer :positive_outcome_count, default: 0, null: false
      t.integer :negative_outcome_count, default: 0, null: false
      t.integer :access_count, default: 0, null: false

      # Metadata
      t.jsonb :tags, default: [], null: false
      t.jsonb :applicable_domains, default: []
      t.jsonb :metadata, default: {}

      t.references :superseded_by, foreign_key: { to_table: :ai_compound_learnings }, type: :uuid

      t.datetime :promoted_at
      t.datetime :last_injected_at
      t.datetime :expires_at
      t.timestamps
    end

    # Add vector column via raw SQL (pgvector gem doesn't integrate with AR migrations)
    execute "ALTER TABLE ai_compound_learnings ADD COLUMN embedding vector(1536)"

    add_index :ai_compound_learnings, [:account_id, :category]
    add_index :ai_compound_learnings, [:account_id, :status]
    add_index :ai_compound_learnings, [:account_id, :scope]
    add_index :ai_compound_learnings, [:ai_agent_team_id, :category]
    add_index :ai_compound_learnings, :importance_score
    add_index :ai_compound_learnings, :effectiveness_score
    add_index :ai_compound_learnings, :tags, using: :gin
    add_index :ai_compound_learnings, :applicable_domains, using: :gin

    execute <<~SQL
      CREATE INDEX idx_compound_learnings_embedding
      ON ai_compound_learnings USING hnsw (embedding vector_cosine_ops);
    SQL
  end

  def down
    drop_table :ai_compound_learnings
  end
end
