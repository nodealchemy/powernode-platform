# frozen_string_literal: true

class CreateAiDataSources < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_data_sources, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 100
      t.string :source_type, null: false, limit: 50
      t.text :description
      t.string :api_base_url, limit: 500
      t.jsonb :capabilities, null: false, default: []
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :rate_limits, null: false, default: {}
      t.jsonb :default_parameters, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.boolean :is_active, null: false, default: true
      t.boolean :requires_auth, null: false, default: false
      t.integer :priority_order, null: false, default: 1000
      t.string :documentation_url, limit: 500
      t.timestamp :last_health_check_at
      t.string :health_status, limit: 20, default: "unknown"
      t.timestamps

      t.index :account_id
      t.index [:account_id, :slug], unique: true, name: "index_ai_data_sources_unique_slug_per_account"
      t.index :source_type
      t.index :is_active
      t.index [:source_type, :is_active]
      t.index :priority_order

      t.foreign_key :accounts, on_delete: :cascade
    end

    add_index :ai_data_sources, :capabilities, using: "gin"

    create_table :ai_data_source_credentials, id: :uuid do |t|
      t.uuid :ai_data_source_id, null: false
      t.uuid :account_id, null: false
      t.string :name, null: false, limit: 255
      t.boolean :is_active, default: true, null: false
      t.boolean :is_default, default: false, null: false
      t.timestamp :expires_at
      t.jsonb :rate_limits, null: false, default: {}
      t.jsonb :usage_stats, null: false, default: {}
      t.timestamp :last_used_at
      t.timestamp :last_test_at
      t.string :last_test_status, limit: 20
      t.string :last_error, limit: 1000
      t.integer :success_count, default: 0, null: false
      t.integer :failure_count, default: 0, null: false
      t.integer :consecutive_failures, default: 0, null: false
      t.string :encrypted_api_key
      t.string :encrypted_api_secret
      t.timestamps

      t.index :ai_data_source_id
      t.index :account_id
      t.index [:account_id, :ai_data_source_id]
      t.index :is_active
      t.index :consecutive_failures

      t.foreign_key :ai_data_sources, on_delete: :cascade
      t.foreign_key :accounts, on_delete: :cascade
    end

    add_index :ai_data_source_credentials,
              [:account_id, :ai_data_source_id, :is_default],
              unique: true, where: "is_default = true",
              name: "index_ai_data_source_credentials_unique_default"
  end
end
