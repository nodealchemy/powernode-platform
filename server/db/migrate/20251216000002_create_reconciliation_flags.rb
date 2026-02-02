# frozen_string_literal: true

class CreateReconciliationFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :reconciliation_flags, id: :uuid do |t|
      t.string :flag_type, null: false
      t.string :provider, null: false
      t.string :local_payment_id, limit: 36
      t.string :external_id
      t.string :status, null: false, default: 'pending'
      t.boolean :requires_manual_review, default: false
      t.json :metadata
      t.text :notes
      t.datetime :resolved_at

      t.timestamps
    end

    add_foreign_key :reconciliation_flags, :payments, column: :local_payment_id
    add_index :reconciliation_flags, :flag_type
    add_index :reconciliation_flags, :provider
    add_index :reconciliation_flags, :status
    add_index :reconciliation_flags, :local_payment_id
    add_index :reconciliation_flags, :external_id
    add_index :reconciliation_flags, :requires_manual_review
  end
end
