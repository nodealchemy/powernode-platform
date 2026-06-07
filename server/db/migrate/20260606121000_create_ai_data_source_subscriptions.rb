# frozen_string_literal: true

# Phase 3 — pull-based subscription/cadence model for governed data sources.
#
# A subscription pairs a (data_source, endpoint) with a poll cadence + the last
# observed change fingerprint (checksum/etag). The server-side MonitorService
# walks due subscriptions, runs the governed QueryService fetch, change-detects
# (etag/If-None-Match or SHA256 of the canonical payload), and on change warms
# the response cache + emits a "data_source_changed" stigmergic signal. The
# worker only fires a thin cron tick.
#
# SWR columns are also added to ai_data_source_endpoints so the cache can serve
# stale-while-revalidate / stale-if-error within bounded windows. Both default
# to nil so the behaviour is fully OFF until an endpoint opts in (zero overhead
# on the existing FetchEnvelope path).
class CreateAiDataSourceSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_data_source_subscriptions, id: :uuid do |t|
      t.references :ai_data_source, type: :uuid, null: false, index: true,
                   foreign_key: { to_table: :ai_data_sources }
      t.references :ai_data_source_endpoint, type: :uuid, null: false, index: true,
                   foreign_key: { to_table: :ai_data_source_endpoints }
      # Optional requesting agent (nullable) — attributes the subscription to an
      # agent for cadence ownership without coupling the FK to agent lifecycle.
      t.uuid :ai_agent_id, index: true

      t.jsonb :params, null: false, default: {}
      t.string :poll_frequency, limit: 50
      t.string :status, null: false, default: "active", limit: 50
      t.datetime :last_polled_at
      t.datetime :next_poll_at
      t.string :last_checksum, limit: 128
      t.string :last_etag, limit: 500
      t.integer :consecutive_failures, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      # Cadence scan index: due_for_poll filters active rows by next_poll_at.
      t.index [:status, :next_poll_at], name: "index_ai_data_source_subscriptions_on_status_and_next_poll"
    end

    # SWR / stale-if-error windows on the endpoint. Partial indexes are not
    # needed (these are read off an already-loaded endpoint row), so we add the
    # bare columns. nil => behaviour disabled.
    add_column :ai_data_source_endpoints, :stale_while_revalidate_seconds, :integer
    add_column :ai_data_source_endpoints, :stale_if_error_seconds, :integer
  end
end
