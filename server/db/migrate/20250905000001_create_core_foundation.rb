# frozen_string_literal: true

class CreateCoreFoundation < ActiveRecord::Migration[8.0]
  def change
    # Enable PostgreSQL extensions
    enable_extension "pgcrypto"

    # Create accounts table - Foundation of the platform
    create_table :accounts, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false, limit: 100
      t.string :subdomain, limit: 30
      t.string :status, null: false, default: 'active', limit: 20
      t.string :stripe_customer_id, limit: 50
      t.string :paypal_customer_id, limit: 50
      t.string :billing_email
      t.string :tax_id
      t.jsonb :settings, default: {}
      t.timestamps null: false

      t.index [ :subdomain ], unique: true, where: "subdomain IS NOT NULL AND subdomain != ''"
      t.index [ :status ]
      t.index [ :stripe_customer_id ], unique: true, where: "stripe_customer_id IS NOT NULL"
      t.index [ :paypal_customer_id ], unique: true, where: "paypal_customer_id IS NOT NULL"
    end

    # Create users table - User accounts within organizations
    create_table :users, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :email, null: false, limit: 255
      t.string :password_digest, null: false
      t.string :first_name, null: false, limit: 50
      t.string :last_name, null: false, limit: 50
      t.string :status, null: false, default: 'active', limit: 20
      t.boolean :email_verified, default: false, null: false
      t.datetime :email_verified_at
      t.string :email_verification_token, limit: 255
      t.datetime :email_verification_token_expires_at
      t.datetime :email_verification_sent_at

      # Security fields
      t.integer :failed_login_attempts, default: 0, null: false
      t.datetime :locked_until
      t.datetime :password_changed_at
      t.datetime :last_login_at
      t.string :last_login_ip, limit: 45

      # Password reset fields
      t.string :reset_token_digest
      t.datetime :reset_token_expires_at

      # User preferences and settings
      t.text :preferences
      t.text :notification_preferences

      # Two-factor authentication fields
      t.boolean :two_factor_enabled, default: false, null: false
      t.string :two_factor_secret
      t.text :backup_codes
      t.datetime :two_factor_backup_codes_generated_at
      t.datetime :two_factor_enabled_at

      t.timestamps null: false

      t.index [ :email ], unique: true
      t.index [ :status ]
      t.index [ :email_verification_token ], unique: true, where: "email_verification_token IS NOT NULL"
      t.index [ :reset_token_digest ], unique: true, where: "reset_token_digest IS NOT NULL"
    end

    # Create password_histories table
    create_table :password_histories, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :password_digest, null: false
      t.datetime :created_at, null: false

      t.index [ :created_at ]
    end

    # Create blacklisted_tokens table
    create_table :blacklisted_tokens, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :token, null: false
      t.string :reason, default: 'logout'
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false

      t.index [ :token ], unique: true
      t.index [ :expires_at ]
    end

    # Create user_tokens table - Traditional token-based authentication
    create_table :user_tokens, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :token_digest, null: false, limit: 128
      t.string :token_type, null: false, default: 'access', limit: 20
      t.string :name, null: true, limit: 100 # For API keys or named tokens
      t.text :permissions, null: true # JSON array of permissions (cached)
      t.string :scopes, null: true, limit: 500 # Comma-separated scopes
      t.datetime :last_used_at
      t.inet :last_used_ip
      t.string :user_agent, limit: 500
      t.datetime :expires_at
      t.boolean :revoked, default: false
      t.datetime :revoked_at
      t.string :revoked_reason, limit: 100
      t.jsonb :metadata, default: {}
      t.timestamps null: false

      # Indexes
      t.index [ :token_digest ], unique: true, name: 'idx_user_tokens_on_token_digest_unique'
      t.index [ :user_id ], name: 'idx_user_tokens_on_user_id'
      t.index [ :user_id, :token_type ], name: 'idx_user_tokens_on_user_id_type'
      t.index [ :token_type ], name: 'idx_user_tokens_on_token_type'
      t.index [ :expires_at ], name: 'idx_user_tokens_on_expires_at'
      t.index [ :revoked ], name: 'idx_user_tokens_on_revoked'
      t.index [ :last_used_at ], name: 'idx_user_tokens_on_last_used_at'
      t.index [ :created_at ], name: 'idx_user_tokens_on_created_at'
    end

    # Create permissions table
    create_table :permissions, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false, limit: 100
      t.string :resource, limit: 100
      t.string :action, limit: 100
      t.string :category, null: false, limit: 50
      t.text :description
      t.timestamps null: false

      t.index [ :name ], unique: true
      t.index [ :resource, :action, :category ], unique: true, name: 'idx_permissions_on_resource_action_category_unique'
      t.index [ :category ]
    end

    # Create roles table
    create_table :roles, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false, limit: 100
      t.string :display_name, limit: 100
      t.text :description
      t.string :role_type, limit: 20
      t.boolean :is_system, default: false, null: false
      t.boolean :immutable, default: false, null: false
      t.timestamps null: false

      t.index [ :name ], unique: true
    end

    # Create role_permissions junction table
    create_table :role_permissions, id: false do |t|
      t.references :role, null: false, foreign_key: true, type: :uuid
      t.references :permission, null: false, foreign_key: true, type: :uuid
      t.timestamp :granted_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.index [ :role_id, :permission_id ], unique: true, name: 'index_role_perms_unique'
      t.index :permission_id, name: 'index_role_perms_on_permission'
    end

    # Create user_roles junction table
    create_table :user_roles, id: false do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :role, null: false, foreign_key: true, type: :uuid
      t.references :granted_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.timestamp :granted_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.index [ :user_id, :role_id ], unique: true, name: 'index_user_roles_unique'
      t.index :role_id, name: 'index_user_roles_on_role'
      t.index :granted_by_id, name: 'index_user_roles_on_granted_by'
    end

    # Create workers table - Background job workers
    create_table :workers, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.uuid :account_id, null: true
      t.string :name, null: false
      t.text :description
      t.string :status, default: 'active'
      t.string :token_digest
      t.jsonb :permissions, default: []
      t.datetime :last_seen_at
      t.timestamps null: false

      t.index [ :name ], unique: true
      t.index [ :status ]
      t.index [ :permissions ], using: :gin
      t.index [ :account_id ]
    end

    # Create worker_roles junction table
    create_table :worker_roles, id: false do |t|
      t.references :worker, null: false, foreign_key: true, type: :uuid
      t.references :role, null: false, foreign_key: true, type: :uuid
      t.timestamp :granted_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.index [ :worker_id, :role_id ], unique: true, name: 'index_worker_roles_unique'
      t.index :role_id, name: 'index_worker_roles_on_role'
    end

    # Create account_delegations table - Cross-account permissions
    create_table :account_delegations, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :delegated_user, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :delegated_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :role, null: true, foreign_key: true, type: :uuid
      t.string :status, default: 'active'
      t.datetime :expires_at
      t.datetime :revoked_at
      t.references :revoked_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.text :notes
      t.timestamps null: false

      t.index [ :account_id, :delegated_user_id ], unique: true, name: 'index_account_delegations_unique'
      t.index [ :status ], name: 'index_account_delegations_on_status'
      t.index [ :expires_at ], name: 'index_account_delegations_on_expires_at'
    end

    # Create delegation_permissions table
    create_table :delegation_permissions, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account_delegation, null: false, foreign_key: true, type: :uuid
      t.references :permission, null: false, foreign_key: true, type: :uuid
      t.timestamps null: false

      t.index [ :account_delegation_id, :permission_id ], unique: true, name: 'index_delegation_permissions_unique'
      t.index :permission_id, name: 'index_delegation_permissions_on_permission'
    end

    # Create invitations table - User invitations
    create_table :invitations, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :inviter, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :email, null: false
      t.string :first_name
      t.string :last_name
      t.string :token, null: false
      t.string :token_digest, null: false
      t.jsonb :role_names, default: [ 'member' ]
      t.string :status, default: 'pending'
      t.datetime :expires_at
      t.datetime :accepted_at
      t.timestamps null: false

      t.index [ :token_digest ], unique: true, name: 'index_invitations_on_token_digest'
      t.index [ :email, :account_id ], unique: true, name: 'index_invitations_on_email_account'
      t.index [ :status ], name: 'index_invitations_on_status'
      t.index [ :expires_at ], name: 'index_invitations_on_expires_at'
      t.index [ :role_names ], using: :gin, name: 'index_invitations_on_role_names'
    end

    # Create impersonation_sessions table
    create_table :impersonation_sessions, id: false do |t|
      t.uuid :id, primary_key: true, null: false, default: -> { 'gen_random_uuid()' }
      t.references :impersonator, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :impersonated_user, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :session_token, null: false
      t.string :reason
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.string :ip_address
      t.string :user_agent
      t.timestamps null: false

      t.index [ :session_token ], unique: true, name: 'index_impersonation_sessions_on_session_token_unique'
      t.index [ :impersonator_id ], name: 'index_impersonation_sessions_on_impersonator'
      t.index [ :impersonated_user_id ], name: 'index_impersonation_sessions_on_impersonated_user'
      t.index [ :started_at ], name: 'index_impersonation_sessions_on_started_at'
      t.index [ :ended_at ], name: 'index_impersonation_sessions_on_ended_at'
    end

    # Add foreign key constraints
    add_foreign_key :workers, :accounts, column: :account_id

    # Add check constraints
    add_check_constraint :accounts, "status IN ('active', 'cancelled', 'suspended')", name: 'valid_account_status'
    add_check_constraint :users, "status IN ('active', 'inactive', 'suspended', 'pending_verification')", name: 'valid_user_status'
    add_check_constraint :permissions, "category IN ('resource', 'admin', 'system')", name: 'valid_permission_category'
    add_check_constraint :account_delegations, "status IN ('active', 'inactive', 'expired')", name: 'valid_delegation_status'
    add_check_constraint :invitations, "status IN ('pending', 'accepted', 'expired', 'cancelled')", name: 'valid_invitation_status'
    add_check_constraint :user_tokens, "token_type IN ('access', 'refresh', 'api_key', '2fa', 'impersonation')", name: 'valid_token_type'
    add_check_constraint :user_tokens, 'expires_at > created_at', name: 'valid_expiration'
    add_check_constraint :user_tokens, 'length(token_digest) >= 32', name: 'valid_token_digest_length'
  end
end
