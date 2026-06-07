# frozen_string_literal: true

# Phase 4b-3a — config-driven TRANSFORM pipeline on canonical data-source
# records.
#
#   - ai_data_source_endpoints.transforms (jsonb default {}): the ordered
#     transform pipeline config consumed by Ai::DataSources::TransformService.
#     Shape: { "pipeline" => [ {op, ...}, ... ] } — an ORDERED array of steps
#     (flatten / unnest / select / rename / computed) applied in sequence to the
#     canonical Array<Hash> records AFTER normalization and BEFORE the response
#     cache write (so the cached payload is the transformed shape). Default {} ==
#     no transforms == records unchanged. No index — config blob read alongside
#     its endpoint row, never queried in isolation (mirrors the pagination /
#     incremental / contract / response_mapping jsonb columns).
#
# Reversible: down drops the column.
class AddTransformsToAiDataSourceEndpoints < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_data_source_endpoints, :transforms, :jsonb, default: {}
  end
end
