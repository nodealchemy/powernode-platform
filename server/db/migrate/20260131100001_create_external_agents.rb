# frozen_string_literal: true

class CreateExternalAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :external_agents, id: :uuid do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: true
      t.references :created_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, type: :uuid

      # Identity
      t.string :name, null: false, limit: 255
      t.text :description
      t.string :slug, limit: 150

      # A2A Discovery
      t.string :agent_card_url, null: false
      t.jsonb :cached_card, default: {}
      t.datetime :card_cached_at
      t.string :card_version

      # Skills and capabilities
      t.jsonb :skills, default: []
      t.jsonb :capabilities, default: {}

      # Status and health
      t.string :status, null: false, default: "active"
      t.datetime :last_health_check
      t.string :health_status
      t.jsonb :health_details, default: {}

      # Authentication configuration
      t.jsonb :authentication, default: {}
      t.string :auth_token_encrypted

      # Usage tracking
      t.integer :task_count, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.decimal :avg_response_time_ms, precision: 10, scale: 2

      # Metadata
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :external_agents, %i[account_id name], unique: true, name: "idx_external_agents_account_name"
    add_index :external_agents, :slug, unique: true, where: "slug IS NOT NULL"
    add_index :external_agents, :status
    add_index :external_agents, :agent_card_url
    add_index :external_agents, :skills, using: :gin
    add_index :external_agents, :capabilities, using: :gin

    # Check constraint for status
    add_check_constraint :external_agents,
                         "status IN ('active', 'inactive', 'error', 'unreachable')",
                         name: "external_agents_status_check"
  end
end
