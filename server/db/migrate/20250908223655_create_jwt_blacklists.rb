# frozen_string_literal: true

class CreateJwtBlacklists < ActiveRecord::Migration[8.0]
  def change
    create_table :jwt_blacklists, id: :uuid do |t|
      t.string :jti, null: false, limit: 100
      t.datetime :expires_at, null: false
      t.uuid :user_id, null: true
      t.string :reason, limit: 100
      t.boolean :user_blacklist, default: false, null: false
      t.text :metadata

      t.timestamps null: false
    end

    # Primary index for fast JTI lookups
    add_index :jwt_blacklists, :jti, unique: true, name: 'index_jwt_blacklists_on_jti'
    
    # Index for cleanup of expired tokens
    add_index :jwt_blacklists, :expires_at, name: 'index_jwt_blacklists_on_expires_at'
    
    # Index for user-specific blacklists
    add_index :jwt_blacklists, [:user_id, :user_blacklist], 
              name: 'index_jwt_blacklists_on_user_id_and_user_blacklist'
    
    # Composite index for active token lookups
    add_index :jwt_blacklists, [:jti, :expires_at], 
              name: 'index_jwt_blacklists_on_jti_and_expires_at'
              
    # Add foreign key constraint to users table
    add_foreign_key :jwt_blacklists, :users, column: :user_id, on_delete: :nullify
  end
end
