class CreateReconciliationReports < ActiveRecord::Migration[8.0]
  def change
    create_table :reconciliation_reports, id: :uuid do |t|
      t.date :reconciliation_date, null: false
      t.string :reconciliation_type, null: false
      t.datetime :date_range_start, null: false
      t.datetime :date_range_end, null: false
      t.integer :discrepancies_count, null: false, default: 0
      t.integer :high_severity_count, null: false, default: 0
      t.integer :medium_severity_count, null: false, default: 0
      t.json :summary

      t.timestamps
    end

    add_index :reconciliation_reports, :reconciliation_date
    add_index :reconciliation_reports, :reconciliation_type
    add_index :reconciliation_reports, :discrepancies_count
    add_index :reconciliation_reports, [:date_range_start, :date_range_end]
  end
end