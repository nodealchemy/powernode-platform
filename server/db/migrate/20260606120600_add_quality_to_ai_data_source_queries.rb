# frozen_string_literal: true

class AddQualityToAiDataSourceQueries < ActiveRecord::Migration[8.0]
  def change
    # Phase 2b quality/quarantine outcome columns on the per-fetch audit log.
    # These are read alongside the owning query row (never queried in isolation),
    # so no standalone indexes are added — adding any would be pure write
    # amplification on this high-volume log table.
    add_column :ai_data_source_queries, :quality_score, :decimal, precision: 5, scale: 4
    add_column :ai_data_source_queries, :quality_passed, :boolean
    add_column :ai_data_source_queries, :quarantined, :boolean, null: false, default: false
    add_column :ai_data_source_queries, :schema_drift, :string, limit: 20
  end
end
