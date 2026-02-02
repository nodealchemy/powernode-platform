# frozen_string_literal: true

class CreateEmailDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :email_deliveries, id: { type: :string, limit: 36 } do |t|
      t.string :recipient_email, null: false
      t.string :subject, null: false
      t.string :email_type, limit: 50, null: false
      t.references :account, null: true, foreign_key: true, type: :string, limit: 36
      t.references :user, null: true, foreign_key: true, type: :string, limit: 36
      t.string :template, limit: 100
      t.text :template_data
      t.string :status, limit: 30, default: 'pending', null: false
      t.string :message_id, limit: 255
      t.datetime :sent_at, precision: nil
      t.datetime :failed_at, precision: nil
      t.text :error_message
      t.integer :retry_count, default: 0, null: false

      t.timestamps
    end

    # Add indexes for common queries (account_id and user_id already indexed by references)
    add_index :email_deliveries, :recipient_email
    add_index :email_deliveries, :email_type
    add_index :email_deliveries, :status
    add_index :email_deliveries, :created_at
    add_index :email_deliveries, [ :status, :created_at ]
    add_index :email_deliveries, [ :email_type, :status ]
  end
end
