class CreateWebhookDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_deliveries, id: :string do |t|
      t.references :webhook_endpoint, null: false, foreign_key: true, type: :string
      
      t.string :event_type, null: false, limit: 100
      t.string :status, null: false, default: 'pending', limit: 30
      t.json :payload
      t.integer :http_status
      t.integer :response_time_ms
      t.text :response_body
      t.json :response_headers
      t.integer :attempt_count, null: false, default: 0
      t.timestamp :next_retry_at
      t.timestamp :completed_at
      t.text :error_message
      t.json :metadata

      t.timestamps null: false
    end

    add_index :webhook_deliveries, :webhook_endpoint_id
    add_index :webhook_deliveries, :event_type
    add_index :webhook_deliveries, :status
    add_index :webhook_deliveries, :next_retry_at
    add_index :webhook_deliveries, :completed_at
    add_index :webhook_deliveries, :created_at
    add_index :webhook_deliveries, [:status, :next_retry_at]
    
    # Add check constraint for status
    execute <<-SQL
      ALTER TABLE webhook_deliveries 
      ADD CONSTRAINT webhook_deliveries_status_check 
      CHECK (status IN ('pending', 'successful', 'failed', 'max_retries_reached'));
    SQL
  end
end
