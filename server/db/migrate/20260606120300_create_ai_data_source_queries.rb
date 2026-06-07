# frozen_string_literal: true

class CreateAiDataSourceQueries < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_data_source_queries, id: :uuid do |t|
      # index: false — the composite [:ai_data_source_id, :created_at] index below
      # already covers FK-only lookups via its leftmost prefix, so a standalone
      # single-column index would be redundant write amplification on this log table.
      t.references :ai_data_source, type: :uuid, null: false, index: false,
                   foreign_key: { to_table: :ai_data_sources }
      t.references :ai_data_source_endpoint, type: :uuid, index: true,
                   foreign_key: { to_table: :ai_data_source_endpoints }
      t.uuid :account_id, index: true
      t.uuid :requesting_agent_id
      t.string :principal, limit: 255
      t.string :purpose, limit: 255
      t.string :params_hash, limit: 128
      t.string :redacted_url, limit: 2000
      t.boolean :redaction_applied, null: false, default: false
      t.string :status, limit: 50
      t.integer :http_status
      t.integer :duration_ms
      t.bigint :bytes_in
      t.bigint :bytes_out
      t.integer :rows_returned
      t.boolean :cached, null: false, default: false
      t.string :served_stage, limit: 50
      t.string :response_sha256, limit: 64
      t.boolean :schema_valid
      t.string :policy_decision, limit: 50
      t.boolean :masking_applied, null: false, default: false
      t.string :correlation_id, limit: 255
      t.decimal :estimated_cost_usd, precision: 12, scale: 6
      t.decimal :actual_cost_usd, precision: 12, scale: 6
      t.text :error
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index [:ai_data_source_id, :created_at]
    end
  end
end
