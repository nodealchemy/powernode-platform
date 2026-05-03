# frozen_string_literal: true

# Adds 'disk_image' to the FileObject category CHECK constraint at the
# database level. The Ruby validation in file_management/object.rb was
# updated in chunk 1, but the matching DB constraint also needs the
# new value or inserts hit PG::CheckViolation.
#
# Plan: docs/plans/wondrous-yawning-anchor.md (Phase 2 — Chunk 4 follow-up).
class AddDiskImageToFileObjectCategoryCheck < ActiveRecord::Migration[8.1]
  CATEGORIES_BEFORE = %w[
    user_upload workflow_output ai_generated temp system import page_content
    sbom_export attestation_proof supply_chain_scan_report
    vendor_compliance vendor_assessment vendor_certificate
  ].freeze

  CATEGORIES_AFTER = (CATEGORIES_BEFORE + %w[disk_image]).freeze

  def up
    execute "ALTER TABLE file_objects DROP CONSTRAINT IF EXISTS file_objects_category_check"
    execute <<~SQL
      ALTER TABLE file_objects ADD CONSTRAINT file_objects_category_check
      CHECK (category IS NULL OR category::text = ANY (ARRAY[#{CATEGORIES_AFTER.map { |c| "'#{c}'::character varying" }.join(', ')}]::text[]))
    SQL
  end

  def down
    execute "ALTER TABLE file_objects DROP CONSTRAINT IF EXISTS file_objects_category_check"
    execute <<~SQL
      ALTER TABLE file_objects ADD CONSTRAINT file_objects_category_check
      CHECK (category IS NULL OR category::text = ANY (ARRAY[#{CATEGORIES_BEFORE.map { |c| "'#{c}'::character varying" }.join(', ')}]::text[]))
    SQL
  end
end
