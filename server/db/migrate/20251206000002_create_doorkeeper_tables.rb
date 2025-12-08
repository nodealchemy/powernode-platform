# frozen_string_literal: true

class CreateDoorkeeperTables < ActiveRecord::Migration[8.0]
  def change
    # OAuth Applications (API clients)
    create_table :oauth_applications, id: :uuid do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret, null: false
      t.text :redirect_uri
      t.string :scopes, default: '', null: false
      t.boolean :confidential, default: true, null: false
      t.references :owner, polymorphic: true, null: true, type: :uuid

      # Custom fields for Powernode
      t.string :description
      t.boolean :trusted, default: false, null: false
      t.boolean :machine_client, default: false, null: false
      t.string :status, default: 'active', null: false
      t.string :rate_limit_tier, default: 'standard'
      t.jsonb :metadata, default: {}

      t.timestamps null: false

      t.index :uid, unique: true
      t.index :owner_id
      t.index :status
      t.index :trusted
    end

    # OAuth Access Grants (authorization codes)
    create_table :oauth_access_grants, id: :uuid do |t|
      t.references :resource_owner, null: false, type: :uuid, index: true
      t.references :application, null: false, type: :uuid, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, default: '', null: false
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :code_challenge
      t.string :code_challenge_method

      t.index :token, unique: true
      # Note: resource_owner_id index is already created by t.references
    end

    # OAuth Access Tokens
    create_table :oauth_access_tokens, id: :uuid do |t|
      t.references :resource_owner, type: :uuid, index: true
      t.references :application, type: :uuid, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in
      t.string :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :previous_refresh_token, default: '', null: false

      # Custom fields
      t.inet :created_from_ip
      t.string :user_agent

      t.index :token, unique: true
      t.index :refresh_token, unique: true
      # Note: resource_owner_id index is already created by t.references
      t.index [:application_id, :created_at]
      t.index :revoked_at
    end

    # Add foreign key for resource_owner to users table
    add_foreign_key :oauth_access_grants, :users, column: :resource_owner_id, on_delete: :cascade
    add_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id, on_delete: :cascade
  end
end
