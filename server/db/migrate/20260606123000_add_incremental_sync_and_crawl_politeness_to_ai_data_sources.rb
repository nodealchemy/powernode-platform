# frozen_string_literal: true

# Phase 5 — incremental sync (high-watermark cursor) + crawl politeness
# (robots.txt + per-host pacing) for governed data sources.
#
#   - ai_data_source_subscriptions.sync_cursor (string, nullable): the
#     incremental high-watermark for a subscription. When the paired endpoint
#     declares +incremental+ config, MonitorService injects this cursor into the
#     fetch params and persists the next cursor extracted from the response via
#     record_poll!(cursor:). Nullable — nil means "no watermark yet" (full
#     fetch). Read off an already-loaded subscription row, so no index (mirrors
#     last_checksum / last_etag).
#   - ai_data_source_endpoints.incremental (jsonb default {}): incremental-sync
#     config consumed by Ai::DataSources::IncrementalSync /  MonitorService —
#     { cursor_param:, cursor_path:, mode: "cursor"|"timestamp" }. Default {} ==
#     OFF (no cursor injection, unchanged behavior). No index — config blob read
#     alongside its endpoint row, never queried in isolation (mirrors the
#     pagination / contract / response_mapping jsonb columns).
#   - ai_data_sources.respect_robots (boolean, null:false default false):
#     per-source opt-in to robots.txt + crawl-delay politeness. OFF by default so
#     existing sources incur zero overhead until enabled (mirrors the Phase 2b
#     opt-in boolean flags on endpoints).
#   - ai_data_sources.crawl_delay_seconds (integer, nullable): minimum interval
#     between requests to a host for this source's per-host pacer; falls back to
#     a service default when nil and overridden by a robots.txt Crawl-delay.
#     Plain scalar read off the loaded source row, so no index (mirrors
#     sla_max_age_seconds / stale_*_seconds).
#
# Reversible: down drops all four columns.
class AddIncrementalSyncAndCrawlPolitenessToAiDataSources < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_data_source_subscriptions, :sync_cursor, :string, limit: 500
    add_column :ai_data_source_endpoints, :incremental, :jsonb, default: {}
    add_column :ai_data_sources, :respect_robots, :boolean, null: false, default: false
    add_column :ai_data_sources, :crawl_delay_seconds, :integer
  end
end
