class CreateServices < ActiveRecord::Migration[8.0]
  def change
    create_table :services, id: :string do |t|
      t.string :name, null: false
      t.text :description
      t.string :token, null: false
      t.string :permissions, null: false, default: 'standard'
      t.string :status, null: false, default: 'active'
      t.references :account, null: true, foreign_key: true, type: :string # nullable for global services
      t.datetime :last_seen_at
      t.integer :request_count, default: 0
      t.datetime :token_regenerated_at

      t.timestamps
    end
    
    # Add indexes for common queries
    add_index :services, :token, unique: true
    add_index :services, :status
    add_index :services, :permissions
    add_index :services, :last_seen_at
  end
end
