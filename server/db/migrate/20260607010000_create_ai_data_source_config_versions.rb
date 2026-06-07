# frozen_string_literal: true

class CreateAiDataSourceConfigVersions < ActiveRecord::Migration[8.0]
  def change
    # Append-only config-version history for a data source. Each row is one
    # CREDENTIAL-FREE manifest snapshot of the source (+ its endpoints) captured
    # by Ai::DataSources::ConfigPortabilityService#snapshot!, classified by who/
    # what produced it (auto|manual|rollback). Mirrors the per-endpoint
    # ai_data_source_schema_versions table's monotonic-version pattern, but scoped
    # to the whole source's PORTABLE config (the export manifest) rather than a
    # single endpoint's observed response schema.
    create_table :ai_data_source_config_versions, id: :uuid do |t|
      # index: false — the composite [ai_data_source_id, version] below covers FK
      # lookups via its leftmost prefix; a standalone FK index would be pure write
      # amplification (same rationale as the schema-versions table).
      t.references :ai_data_source, type: :uuid, null: false, index: false,
                   foreign_key: { to_table: :ai_data_sources }
      t.references :account, type: :uuid, null: false, index: true,
                   foreign_key: { to_table: :accounts }
      t.integer :version, null: false, default: 1
      # The credential-free export manifest (source + endpoints, MINUS secrets).
      t.jsonb :manifest, null: false, default: {}
      # Provenance of the snapshot: "auto" | "manual" | "rollback".
      t.string :created_by_type, null: false, default: "manual", limit: 20
      t.string :note, limit: 500
      t.timestamps

      # One row per (source, version). The composite covers the latest-version
      # lookup (ai_data_source_id leftmost) without a redundant single-column FK
      # index — same write-amplification rationale as the schema-versions index.
      t.index [:ai_data_source_id, :version], unique: true,
              name: "index_ai_ds_config_versions_unique_version"
    end
  end
end
