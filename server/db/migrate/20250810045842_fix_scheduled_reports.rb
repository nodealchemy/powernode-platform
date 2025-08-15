class FixScheduledReports < ActiveRecord::Migration[8.0]
  def up
    # Create the table
    create_table :scheduled_reports, id: :string do |t|
      t.string :report_type, null: false
      t.string :frequency, null: false
      t.text :recipients
      t.string :format, default: 'pdf'
      t.references :account, foreign_key: true, type: :string
      t.references :user, null: false, foreign_key: true, type: :string
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.boolean :active, default: true

      t.timestamps
    end

    # Add indexes carefully
    begin
      add_index :scheduled_reports, [:account_id, :active] unless index_exists?(:scheduled_reports, [:account_id, :active])
    rescue StandardError => e
      Rails.logger.warn "Could not create account_id, active index: #{e.message}"
    end

    begin
      add_index :scheduled_reports, [:next_run_at, :active] unless index_exists?(:scheduled_reports, [:next_run_at, :active])
    rescue StandardError => e
      Rails.logger.warn "Could not create next_run_at, active index: #{e.message}"
    end

    begin
      add_index :scheduled_reports, :user_id unless index_exists?(:scheduled_reports, :user_id)
    rescue StandardError => e
      Rails.logger.warn "Could not create user_id index: #{e.message}"
    end
  end

  def down
    drop_table :scheduled_reports if table_exists?(:scheduled_reports)
  end
end
