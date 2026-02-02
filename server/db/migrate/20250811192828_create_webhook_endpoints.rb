class CreateWebhookEndpoints < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_endpoints, id: :string do |t|
      t.string :url, null: false, limit: 2000
      t.string :description, limit: 500
      t.string :status, null: false, default: 'active', limit: 20
      t.text :secret_token
      t.string :content_type, null: false, default: 'application/json', limit: 100
      t.integer :timeout_seconds, null: false, default: 30
      t.integer :retry_limit, null: false, default: 3
      t.string :retry_backoff, null: false, default: 'exponential', limit: 20
      t.json :event_types
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.timestamp :last_delivery_at
      t.json :metadata

      # Association columns
      t.references :created_by, null: true, foreign_key: { to_table: :users }, type: :string

      t.timestamps null: false
    end

    add_index :webhook_endpoints, :url
    add_index :webhook_endpoints, :status
    add_index :webhook_endpoints, :created_by_id
    add_index :webhook_endpoints, :last_delivery_at

    # Add check constraints
    execute <<-SQL
      ALTER TABLE webhook_endpoints#{' '}
      ADD CONSTRAINT webhook_endpoints_status_check#{' '}
      CHECK (status IN ('active', 'inactive'));
    SQL

    execute <<-SQL
      ALTER TABLE webhook_endpoints#{' '}
      ADD CONSTRAINT webhook_endpoints_content_type_check#{' '}
      CHECK (content_type IN ('application/json', 'application/x-www-form-urlencoded'));
    SQL

    execute <<-SQL
      ALTER TABLE webhook_endpoints#{' '}
      ADD CONSTRAINT webhook_endpoints_retry_backoff_check#{' '}
      CHECK (retry_backoff IN ('linear', 'exponential'));
    SQL
  end
end
