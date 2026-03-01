# frozen_string_literal: true

class UpdateReportTypeConstraint < ActiveRecord::Migration[8.1]
  def up
    # Remove old constraint
    execute <<-SQL
      ALTER TABLE supply_chain_reports
      DROP CONSTRAINT IF EXISTS check_reports_type;
    SQL

    # Add updated constraint with additional report types
    execute <<-SQL
      ALTER TABLE supply_chain_reports
      ADD CONSTRAINT check_reports_type
      CHECK (report_type IN (
        'sbom_export',
        'vulnerability',
        'vulnerability_report',
        'license_report',
        'attribution',
        'compliance',
        'compliance_summary',
        'vendor_risk',
        'vendor_assessment',
        'custom'
      ));
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE supply_chain_reports
      DROP CONSTRAINT IF EXISTS check_reports_type;
    SQL

    execute <<-SQL
      ALTER TABLE supply_chain_reports
      ADD CONSTRAINT check_reports_type
      CHECK (report_type IN (
        'sbom_export',
        'vulnerability_report',
        'license_report',
        'attribution',
        'compliance_summary',
        'vendor_assessment',
        'custom'
      ));
    SQL
  end
end
