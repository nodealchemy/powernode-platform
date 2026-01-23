# frozen_string_literal: true

class AddSupplyChainFileCategories < ActiveRecord::Migration[8.0]
  def up
    # Update check constraint to include new supply chain categories
    execute <<-SQL
      ALTER TABLE file_objects DROP CONSTRAINT IF EXISTS file_objects_category_check;
      ALTER TABLE file_objects ADD CONSTRAINT file_objects_category_check
        CHECK (category IS NULL OR category IN (
          'user_upload', 'workflow_output', 'ai_generated', 'temp', 'system', 'import', 'page_content',
          'sbom_export', 'attestation_proof', 'supply_chain_scan_report',
          'vendor_compliance', 'vendor_assessment', 'vendor_certificate'
        ));
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE file_objects DROP CONSTRAINT IF EXISTS file_objects_category_check;
      ALTER TABLE file_objects ADD CONSTRAINT file_objects_category_check
        CHECK (category IS NULL OR category IN (
          'user_upload', 'workflow_output', 'ai_generated', 'temp', 'system', 'import', 'page_content'
        ));
    SQL
  end
end
