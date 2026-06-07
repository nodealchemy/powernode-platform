# frozen_string_literal: true

class CreateAiDataSourceSchemaVersionsAndExpectations < ActiveRecord::Migration[8.0]
  def change
    # Per-endpoint schema version history. Each row is one observed/declared schema
    # snapshot, classified against the prior version (initial|none|additive|breaking)
    # with the structural diff retained for drift auditing.
    create_table :ai_data_source_schema_versions, id: :uuid do |t|
      # index: false — the composite [endpoint_id, version] below covers FK lookups
      # via its leftmost prefix; a standalone FK index would be write amplification.
      t.references :ai_data_source_endpoint, type: :uuid, null: false, index: false,
                   foreign_key: { to_table: :ai_data_source_endpoints }
      t.integer :version, null: false, default: 1
      t.jsonb :schema, null: false, default: {}
      t.string :checksum, limit: 64
      t.string :classification, null: false, default: "initial", limit: 20
      t.jsonb :diff, null: false, default: {}
      t.timestamps

      # One row per (endpoint, version). The composite covers the
      # latest-version lookup (endpoint_id leftmost) without a redundant
      # single-column FK index — same write-amplification rationale as the
      # query log's composite index.
      t.index [:ai_data_source_endpoint_id, :version], unique: true,
              name: "index_ai_ds_schema_versions_unique_version"
    end

    # Per-endpoint data-quality expectations (Great-Expectations-style rules) run
    # over canonical records by Ai::DataSources::QualityService.
    create_table :ai_data_source_expectations, id: :uuid do |t|
      t.references :ai_data_source_endpoint, type: :uuid, null: false, index: true,
                   foreign_key: { to_table: :ai_data_source_endpoints }
      t.string :name, null: false, limit: 255
      t.string :rule_type, null: false, limit: 50
      t.jsonb :config, null: false, default: {}
      t.string :severity, null: false, default: "warn", limit: 20
      t.boolean :is_active, null: false, default: true
      t.timestamps
    end
  end
end
