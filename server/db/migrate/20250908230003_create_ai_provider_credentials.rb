# frozen_string_literal: true

class CreateAiProviderCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_provider_credentials, id: :uuid do |t|
      t.uuid :ai_provider_id, null: false
      t.uuid :account_id, null: false
      t.string :name, null: false, limit: 255
      t.text :encrypted_credentials, null: false
      t.string :encryption_key_id, limit: 50
      t.boolean :is_active, default: true
      t.boolean :is_default, default: false
      t.timestamp :expires_at
      t.jsonb :access_scopes, default: []
      t.jsonb :rate_limits, default: {}
      t.jsonb :usage_stats, default: {}
      t.timestamp :last_used_at
      t.string :last_error
      t.integer :consecutive_failures, default: 0
      t.timestamps

      t.index :ai_provider_id
      t.index :account_id
      t.index [ :account_id, :ai_provider_id ]
      t.index [ :account_id, :is_default ]
      t.index :is_active
      t.index :expires_at
      t.index :last_used_at
      t.index :consecutive_failures

      t.foreign_key :ai_providers, on_delete: :cascade
      t.foreign_key :accounts, on_delete: :cascade
    end

    add_index :ai_provider_credentials, [ :account_id, :ai_provider_id, :is_default ],
              unique: true, where: "is_default = true",
              name: 'index_ai_provider_credentials_unique_default'
  end
end
