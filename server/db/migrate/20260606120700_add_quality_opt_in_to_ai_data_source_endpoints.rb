# frozen_string_literal: true

class AddQualityOptInToAiDataSourceEndpoints < ActiveRecord::Migration[8.0]
  def change
    # Phase 2b opt-in flags + SLA/ownership/contract metadata on endpoints. All
    # observability stages (schema-drift tracking, quality checks, quarantine) are
    # OFF by default so existing endpoints incur zero overhead until enabled.
    add_column :ai_data_source_endpoints, :track_schema, :boolean, null: false, default: false
    add_column :ai_data_source_endpoints, :quality_checks_enabled, :boolean, null: false, default: false
    add_column :ai_data_source_endpoints, :quarantine_on_failure, :boolean, null: false, default: false
    add_column :ai_data_source_endpoints, :sla_max_age_seconds, :integer
    add_column :ai_data_source_endpoints, :owner, :string, limit: 255
    add_column :ai_data_source_endpoints, :contract, :jsonb, default: {}
  end
end
