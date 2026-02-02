class CreateApiKeyUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :api_key_usages, id: :string do |t|
      t.references :api_key, null: false, foreign_key: true, type: :string

      t.string :endpoint, null: false, limit: 500
      t.string :http_method, null: false, limit: 10
      t.integer :status_code, null: false
      t.integer :request_count, null: false, default: 1
      t.string :ip_address, limit: 45
      t.text :user_agent
      t.json :metadata

      t.timestamps null: false
    end

    add_index :api_key_usages, :api_key_id
    add_index :api_key_usages, :endpoint
    add_index :api_key_usages, :http_method
    add_index :api_key_usages, :status_code
    add_index :api_key_usages, :ip_address
    add_index :api_key_usages, :created_at
    add_index :api_key_usages, [ :api_key_id, :created_at ]
    add_index :api_key_usages, [ :status_code, :created_at ]

    # Add check constraint for HTTP method
    execute <<-SQL
      ALTER TABLE api_key_usages#{' '}
      ADD CONSTRAINT api_key_usages_http_method_check#{' '}
      CHECK (http_method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE'));
    SQL
  end
end
