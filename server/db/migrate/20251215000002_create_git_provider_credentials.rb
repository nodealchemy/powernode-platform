# frozen_string_literal: true

class CreateGitProviderCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :git_provider_credentials, id: :uuid do |t|
      t.references :git_provider, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :name, null: false, limit: 255
      t.string :auth_type, null: false, limit: 30
      t.text :encrypted_credentials, null: false
      t.string :encryption_key_id, limit: 50
      t.string :external_username, limit: 255
      t.string :external_user_id, limit: 255
      t.string :external_avatar_url, limit: 500
      t.jsonb :scopes, default: []
      t.boolean :is_active, default: true
      t.boolean :is_default, default: false
      t.timestamp :expires_at
      t.timestamp :last_used_at
      t.timestamp :last_test_at
      t.string :last_test_status, limit: 30
      t.string :last_error, limit: 1000
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.integer :consecutive_failures, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :git_provider_credentials, %i[account_id git_provider_id]
    add_index :git_provider_credentials, %i[account_id is_default]
    add_index :git_provider_credentials, :is_active
    add_index :git_provider_credentials, :auth_type
    add_index :git_provider_credentials, :consecutive_failures
    add_index :git_provider_credentials,
              %i[account_id git_provider_id is_default],
              unique: true,
              where: "is_default = true",
              name: "idx_git_creds_unique_default"
  end
end
