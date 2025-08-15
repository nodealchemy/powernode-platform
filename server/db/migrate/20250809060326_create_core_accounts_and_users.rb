class CreateCoreAccountsAndUsers < ActiveRecord::Migration[8.0]
  def change
    # Create accounts table
    create_table :accounts, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :name, null: false, limit: 100
      t.string :subdomain, limit: 30
      t.string :status, null: false, default: 'active', limit: 20
      t.text :settings, default: '{}'
      
      # Payment fields
      t.string :stripe_customer_id, limit: 50
      t.string :paypal_customer_id, limit: 50
      
      t.timestamps null: false
      
      t.index [:subdomain], unique: true, where: "subdomain IS NOT NULL AND subdomain != ''"
      t.index [:status]
      t.index [:stripe_customer_id], unique: true, where: "stripe_customer_id IS NOT NULL"
      t.index [:paypal_customer_id], unique: true, where: "paypal_customer_id IS NOT NULL"
    end

    # Create users table
    create_table :users, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :account_id, null: false, limit: 36
      t.string :email, null: false, limit: 255
      t.string :password_digest, null: false
      t.string :first_name, null: false, limit: 50
      t.string :last_name, null: false, limit: 50
      t.string :status, null: false, default: 'active', limit: 20
      t.boolean :email_verified, default: false, null: false
      t.datetime :email_verified_at
      t.string :email_verification_token, limit: 255
      t.datetime :email_verification_token_expires_at
      
      # Security fields
      t.integer :failed_login_attempts, default: 0, null: false
      t.datetime :locked_until
      t.datetime :password_changed_at
      t.datetime :last_login_at
      t.string :last_login_ip, limit: 45
      
      # Password reset fields
      t.string :reset_token_digest
      t.datetime :reset_token_expires_at
      
      t.timestamps null: false
      
      t.foreign_key :accounts, column: :account_id
      t.index [:account_id]
      t.index [:email], unique: true
      t.index [:status]
      t.index [:email_verification_token], unique: true, where: "email_verification_token IS NOT NULL"
      t.index [:reset_token_digest], unique: true, where: "reset_token_digest IS NOT NULL"
    end

    # Create password_histories table
    create_table :password_histories, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :user_id, null: false, limit: 36
      t.string :password_digest, null: false
      t.datetime :created_at, null: false
      
      t.foreign_key :users, column: :user_id
      t.index [:user_id]
      t.index [:created_at]
    end

    # Create blacklisted_tokens table
    create_table :blacklisted_tokens, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :user_id, null: false, limit: 36
      t.string :token, null: false
      t.string :reason, default: 'logout'
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
      
      t.foreign_key :users, column: :user_id
      t.index [:user_id]
      t.index [:token], unique: true
      t.index [:expires_at]
    end
  end
end