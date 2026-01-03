# frozen_string_literal: true

class CreateGitWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :git_webhook_events, id: :uuid do |t|
      t.references :git_repository, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :git_provider, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :event_type, null: false, limit: 100
      t.string :action, limit: 50
      t.string :delivery_id, limit: 255
      t.string :status, null: false, limit: 30, default: "pending"
      t.jsonb :payload, null: false
      t.jsonb :headers, default: {}
      t.string :sender_username, limit: 255
      t.string :sender_id, limit: 255
      t.string :ref, limit: 500
      t.string :sha, limit: 64
      t.text :error_message
      t.integer :retry_count, default: 0
      t.timestamp :processed_at
      t.jsonb :processing_result, default: {}
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :git_webhook_events, :event_type
    add_index :git_webhook_events, :status
    add_index :git_webhook_events, :delivery_id
    add_index :git_webhook_events, %i[git_repository_id event_type]
    add_index :git_webhook_events, %i[account_id created_at]
    add_index :git_webhook_events, :created_at
    add_index :git_webhook_events, %i[status retry_count]
  end
end
