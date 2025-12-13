# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :notification_type, null: false
      t.string :title, null: false
      t.text :message, null: false
      t.string :severity, null: false, default: 'info'
      t.string :action_url
      t.string :action_label
      t.string :icon
      t.string :category, default: 'general'
      t.json :metadata, default: {}
      t.datetime :read_at
      t.datetime :dismissed_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :notifications, [ :user_id, :read_at ]
    add_index :notifications, [ :account_id, :created_at ]
    add_index :notifications, [ :user_id, :created_at ]
    add_index :notifications, :notification_type
    add_index :notifications, :category
    add_index :notifications, :expires_at
  end
end
