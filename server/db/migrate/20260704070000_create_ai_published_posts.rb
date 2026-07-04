# frozen_string_literal: true

# Growth analytics (G1) — provenance for a post published through a connected
# data-source's write endpoint (e.g. x-com's "Create post", POST /2/tweets).
# One row per successfully published post; Ai::Growth::PublishedPostRecorder
# creates these off the FetchEnvelope returned by the governed
# Ai::DataSources::QueryService pipeline. Ai::PostEngagementSnapshot (next
# migration) records the per-post engagement time-series against this table.
class CreateAiPublishedPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_published_posts, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :ai_data_source_id, null: false
      t.uuid :ai_data_source_endpoint_id # nullable — survives the endpoint definition being deleted (see :nullify below)
      t.uuid :requesting_agent_id # the agent that dispatched the publish, if any

      t.string :source_type, null: false       # denormalized data_source.source_type at publish time
      t.string :external_id, null: false        # provider's post id (tweet id, status id, listing name, ...)
      t.text :content                            # best-effort published text, extracted from the write response
      t.datetime :published_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # A given data source can never report the same external post id twice —
    # the recorder upserts on this pair so a retried/replayed write is a no-op.
    add_index :ai_published_posts, %i[ai_data_source_id external_id], unique: true
    add_index :ai_published_posts, :account_id
    add_index :ai_published_posts, :ai_data_source_endpoint_id
    add_index :ai_published_posts, :requesting_agent_id
  end
end
