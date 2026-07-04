# frozen_string_literal: true

# Growth analytics (G1) — one row per governed engagement-metrics poll of a
# published post (Ai::Growth::EngagementIngestionService), forming a
# per-post time-series. High-frequency operational data (like
# ai_data_source_queries), so no Auditable concern on the model.
class CreateAiPostEngagementSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_post_engagement_snapshots, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :ai_published_post_id, null: false

      # Common cross-provider engagement fields, nullable — populated only when
      # the source's FIELD_MAP maps them (see EngagementIngestionService).
      t.integer :likes_count
      t.integer :reposts_count
      t.integer :replies_count
      t.integer :impressions_count

      t.jsonb :raw_metrics, null: false, default: {} # the metrics endpoint's canonical record, unmapped
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :ai_post_engagement_snapshots, %i[ai_published_post_id captured_at],
              name: "index_ai_post_engagement_snapshots_on_post_and_captured_at"
    add_index :ai_post_engagement_snapshots, :account_id
  end
end
