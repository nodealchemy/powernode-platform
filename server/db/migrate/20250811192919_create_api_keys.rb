class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys, id: :string do |t|
      t.string :name, null: false, limit: 100
      t.text :description
      t.string :key_hash, null: false, limit: 64
      t.string :key_prefix, null: false, limit: 20
      t.string :key_suffix, null: false, limit: 10
      t.string :status, null: false, default: 'active', limit: 20
      t.json :scopes
      t.timestamp :expires_at
      t.timestamp :last_used_at
      t.integer :usage_count, null: false, default: 0
      t.integer :rate_limit_per_hour
      t.integer :rate_limit_per_day
      t.json :allowed_ips
      t.json :metadata
      
      # Association columns
      t.references :created_by, null: true, foreign_key: { to_table: :users }, type: :string
      t.references :account, null: true, foreign_key: true, type: :string

      t.timestamps null: false
    end

    add_index :api_keys, :key_hash, unique: true
    add_index :api_keys, :status
    add_index :api_keys, :created_by_id
    add_index :api_keys, :account_id
    add_index :api_keys, :expires_at
    add_index :api_keys, :last_used_at
    add_index :api_keys, :usage_count
    add_index :api_keys, [:status, :expires_at]
    
    # Add check constraint for status
    execute <<-SQL
      ALTER TABLE api_keys 
      ADD CONSTRAINT api_keys_status_check 
      CHECK (status IN ('active', 'revoked', 'expired'));
    SQL
  end
end
