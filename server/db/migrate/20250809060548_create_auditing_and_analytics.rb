class CreateAuditingAndAnalytics < ActiveRecord::Migration[8.0]
  def change
    # Create audit_logs table
    create_table :audit_logs, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :user_id, limit: 36
      t.string :account_id, null: false, limit: 36
      t.string :action, null: false, limit: 50
      t.string :resource_type, null: false, limit: 100
      t.string :resource_id, null: false, limit: 36
      t.string :source, null: false, default: 'web', limit: 20
      t.text :old_values
      t.text :new_values
      t.text :metadata, default: '{}'
      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 500
      t.datetime :created_at, null: false
      
      t.foreign_key :users, column: :user_id, on_delete: :nullify
      t.foreign_key :accounts, column: :account_id
      t.index [:user_id]
      t.index [:account_id]
      t.index [:action]
      t.index [:resource_type]
      t.index [:resource_id]
      t.index [:source]
      t.index [:created_at]
      t.index [:resource_type, :resource_id]
    end

    # Create webhook_events table
    create_table :webhook_events, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :account_id, limit: 36
      t.string :provider, null: false, limit: 20
      t.string :event_type, null: false, limit: 100
      t.string :external_id, null: false, limit: 100
      t.text :payload, null: false
      t.string :status, null: false, default: 'pending', limit: 20
      t.datetime :processed_at
      t.text :error_message
      t.integer :retry_count, null: false, default: 0
      t.datetime :created_at, null: false
      
      t.foreign_key :accounts, column: :account_id, on_delete: :nullify
      t.index [:account_id]
      t.index [:provider]
      t.index [:event_type]
      t.index [:external_id]
      t.index [:status]
      t.index [:created_at]
      t.index [:provider, :external_id], unique: true
    end

    # Create revenue_snapshots table
    create_table :revenue_snapshots, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :account_id, limit: 36
      t.date :snapshot_date, null: false
      t.bigint :mrr_cents, null: false, default: 0
      t.bigint :arr_cents, null: false, default: 0
      t.integer :active_subscriptions, null: false, default: 0
      t.integer :new_subscriptions, null: false, default: 0
      t.integer :churned_subscriptions, null: false, default: 0
      t.integer :upgraded_subscriptions, null: false, default: 0
      t.integer :downgraded_subscriptions, null: false, default: 0
      t.string :currency, null: false, default: 'USD', limit: 3
      t.text :metadata, default: '{}'
      t.datetime :created_at, null: false
      
      t.foreign_key :accounts, column: :account_id, on_delete: :cascade
      t.index [:account_id]
      t.index [:snapshot_date]
      t.index [:currency]
      t.index [:account_id, :snapshot_date], unique: true, where: "account_id IS NOT NULL"
      t.index [:snapshot_date], unique: true, where: "account_id IS NULL", name: 'index_revenue_snapshots_on_global_snapshot_date'
    end

    # Create invitations table
    create_table :invitations, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :account_id, null: false, limit: 36
      t.string :inviter_id, null: false, limit: 36
      t.string :role_id, limit: 36
      t.string :email, null: false, limit: 255
      t.string :first_name, limit: 50
      t.string :last_name, limit: 50
      t.string :token, null: false, limit: 255
      t.string :status, null: false, default: 'pending', limit: 20
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.text :message
      t.timestamps null: false
      
      t.foreign_key :accounts, column: :account_id
      t.foreign_key :users, column: :inviter_id
      t.foreign_key :roles, column: :role_id, on_delete: :nullify
      t.index [:account_id]
      t.index [:inviter_id]
      t.index [:role_id]
      t.index [:email]
      t.index [:token], unique: true
      t.index [:status]
      t.index [:expires_at]
    end

    # Create account_delegations table
    create_table :account_delegations, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :account_id, null: false, limit: 36
      t.string :delegated_user_id, null: false, limit: 36
      t.string :delegated_by_id, null: false, limit: 36
      t.string :role_id, limit: 36
      t.string :status, null: false, default: 'active', limit: 20
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.string :revoked_by, limit: 36
      t.text :notes
      t.timestamps null: false
      
      t.foreign_key :accounts, column: :account_id
      t.foreign_key :users, column: :delegated_user_id
      t.foreign_key :users, column: :delegated_by_id
      t.foreign_key :roles, column: :role_id, on_delete: :nullify
      t.index [:account_id]
      t.index [:delegated_user_id]
      t.index [:delegated_by_id]
      t.index [:role_id]
      t.index [:status]
      t.index [:expires_at]
      t.index [:account_id, :delegated_user_id], unique: true
    end
  end
end