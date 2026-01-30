# frozen_string_literal: true

class AddMissingColumnsToReportRequests < ActiveRecord::Migration[8.0]
  def up
    # Add missing columns needed by ReportsController and specs
    change_table :report_requests do |t|
      t.string :name, limit: 255 unless column_exists?(:report_requests, :name)
      t.string :format, limit: 20, default: "pdf" unless column_exists?(:report_requests, :format)
      t.string :file_url unless column_exists?(:report_requests, :file_url)
      t.integer :file_size unless column_exists?(:report_requests, :file_size)
      t.string :content_type, limit: 100 unless column_exists?(:report_requests, :content_type)
    end

    # Update the status check constraint to include 'processing' and 'cancelled'
    if constraint_exists?(:report_requests, "valid_report_request_status")
      remove_check_constraint :report_requests, name: "valid_report_request_status"
    end

    add_check_constraint :report_requests,
      "status IN ('pending', 'generating', 'processing', 'completed', 'failed', 'expired', 'cancelled')",
      name: "valid_report_request_status"

    # Backfill name from report_type for existing records
    execute <<-SQL
      UPDATE report_requests SET name = report_type WHERE name IS NULL;
    SQL
  end

  def down
    remove_column :report_requests, :name if column_exists?(:report_requests, :name)
    remove_column :report_requests, :format if column_exists?(:report_requests, :format)
    remove_column :report_requests, :file_url if column_exists?(:report_requests, :file_url)
    remove_column :report_requests, :file_size if column_exists?(:report_requests, :file_size)
    remove_column :report_requests, :content_type if column_exists?(:report_requests, :content_type)

    if constraint_exists?(:report_requests, "valid_report_request_status")
      remove_check_constraint :report_requests, name: "valid_report_request_status"
    end

    add_check_constraint :report_requests,
      "status IN ('pending', 'generating', 'completed', 'failed', 'expired')",
      name: "valid_report_request_status"
  end

  private

  def constraint_exists?(table, name)
    query = <<-SQL
      SELECT 1 FROM pg_constraint
      WHERE conname = '#{name}'
      AND conrelid = '#{table}'::regclass
    SQL
    ActiveRecord::Base.connection.select_value(query).present?
  end
end
