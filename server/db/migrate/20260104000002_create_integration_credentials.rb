# frozen_string_literal: true

class CreateIntegrationCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_credentials, id: :uuid do |t|
      # Relationships
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by_user, foreign_key: { to_table: :users }, type: :uuid

      # Credential Identity
      t.string :name, null: false
      t.string :credential_type, null: false  # github_app, oauth2, api_key, bearer_token, basic_auth

      # Encrypted Storage
      t.text :encrypted_credentials, null: false
      t.string :encryption_key_id, null: false

      # OAuth2 Specific
      t.datetime :token_expires_at
      t.text :encrypted_refresh_token

      # Scopes & Permissions
      t.jsonb :scopes, default: []  # List of granted scopes
      t.jsonb :metadata, default: {}  # Additional metadata

      # Status & Health
      t.boolean :is_active, default: true
      t.datetime :last_used_at
      t.datetime :last_validated_at
      t.string :validation_status  # valid, invalid, expired, unknown
      t.integer :consecutive_failures, default: 0
      t.text :last_error

      # Expiration & Rotation
      t.datetime :expires_at
      t.datetime :rotated_at
      t.uuid :rotated_from_id

      t.timestamps
    end

    add_index :integration_credentials, [:account_id, :name], unique: true
    add_index :integration_credentials, :credential_type
    add_index :integration_credentials, :is_active
    add_index :integration_credentials, :expires_at
    add_index :integration_credentials, [:account_id, :credential_type], name: "idx_credentials_account_type"
  end
end
