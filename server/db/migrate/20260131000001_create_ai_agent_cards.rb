# frozen_string_literal: true

class CreateAiAgentCards < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_cards, id: :uuid do |t|
      # Relationships
      t.references :ai_agent, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      # A2A Identity
      t.string :name, null: false
      t.text :description
      t.string :protocol_version, default: "0.3", null: false

      # A2A Capabilities
      t.jsonb :capabilities, default: {}, null: false  # skills, input/output schemas, supported_modes
      t.jsonb :authentication, default: {}, null: false  # supported auth methods (api_key, oauth, bearer)
      t.jsonb :default_input_modes, default: [ "application/json" ], null: false
      t.jsonb :default_output_modes, default: [ "application/json" ], null: false

      # External Exposure
      t.string :endpoint_url  # URL for external A2A access
      t.string :visibility, default: "private", null: false  # private, internal, public

      # Discovery Metadata
      t.string :provider_name  # Organization/provider name
      t.string :provider_url
      t.jsonb :tags, default: [], null: false
      t.text :documentation_url

      # Status & Versioning
      t.string :status, default: "active", null: false  # active, inactive, deprecated
      t.string :card_version, default: "1.0.0", null: false
      t.datetime :published_at
      t.datetime :deprecated_at

      # Metrics
      t.integer :task_count, default: 0, null: false
      t.integer :success_count, default: 0, null: false
      t.integer :failure_count, default: 0, null: false
      t.decimal :avg_response_time_ms, precision: 10, scale: 2

      t.timestamps
    end

    add_index :ai_agent_cards, [ :account_id, :name ], unique: true, name: "idx_agent_cards_account_name"
    add_index :ai_agent_cards, :visibility
    add_index :ai_agent_cards, :status
    add_index :ai_agent_cards, :protocol_version
    add_index :ai_agent_cards, :tags, using: :gin
    add_index :ai_agent_cards, :capabilities, using: :gin

    add_check_constraint :ai_agent_cards,
      "visibility IN ('private', 'internal', 'public')",
      name: "ai_agent_cards_visibility_check"

    add_check_constraint :ai_agent_cards,
      "status IN ('active', 'inactive', 'deprecated')",
      name: "ai_agent_cards_status_check"
  end
end
