class CreateReconciliationInvestigations < ActiveRecord::Migration[8.0]
  def change
    create_table :reconciliation_investigations, id: :uuid do |t|
      t.string :investigation_type, null: false
      t.string :local_payment_id, limit: 36
      t.string :provider_payment_id
      t.integer :local_amount, null: false
      t.integer :provider_amount, null: false
      t.integer :amount_difference, null: false
      t.string :status, null: false, default: 'pending'
      t.boolean :requires_investigation, default: false
      t.json :findings
      t.json :corrective_actions
      t.string :resolution_type
      t.integer :amount_corrected
      t.datetime :investigation_started_at
      t.datetime :resolved_at
      t.datetime :closed_at

      t.timestamps
    end

    add_foreign_key :reconciliation_investigations, :payments, column: :local_payment_id
    add_index :reconciliation_investigations, :investigation_type
    add_index :reconciliation_investigations, :status
    add_index :reconciliation_investigations, :local_payment_id
    add_index :reconciliation_investigations, :provider_payment_id
    add_index :reconciliation_investigations, :requires_investigation
    add_index :reconciliation_investigations, :amount_difference
  end
end
