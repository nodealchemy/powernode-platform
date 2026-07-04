# frozen_string_literal: true

# Content drafting (D1) — a persisted, REVIEWABLE draft of provider-ready
# content generated from a knowledge base + a brand-voice profile, targeting
# one connected data source (Ai::DataSource). Created by
# Ai::Growth::ContentDraftingService via the platform LLM (Ai::Agent-resolved
# model, never hardcoded) — never auto-published. D2 owns the approval-gated
# publish/scheduling flow that advances a draft's status past "draft" and
# ultimately dispatches it (through the same Ai::Tools::DataSourceTool /
# CrossPostService choke point every other write already goes through).
class CreateAiContentDrafts < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_content_drafts, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :ai_data_source_id, null: false # target connected provider
      t.uuid :ai_knowledge_base_id # KB the content was drafted from, if any
      t.uuid :requesting_agent_id # the content_generator agent that drafted it
      t.uuid :created_by_id # the user who requested the draft, if any

      t.string :status, null: false, default: "draft"      # draft/pending_review/approved/rejected/published (D2 advances past draft)
      t.string :source_type, null: false                    # denormalized data_source.source_type at draft time
      t.text :content, null: false                          # primary post text (first thread segment when split)
      t.jsonb :segments, null: false, default: []            # ordered thread parts; [content] when not split
      t.jsonb :brand_voice, null: false, default: {}         # tone/voice profile used for this draft
      t.jsonb :metadata, null: false, default: {}            # brief, kb chunk ids, char counts, truncation flags, ...

      t.timestamps
    end

    add_index :ai_content_drafts, :account_id
    add_index :ai_content_drafts, :ai_data_source_id
    add_index :ai_content_drafts, :ai_knowledge_base_id
    add_index :ai_content_drafts, :requesting_agent_id
    add_index :ai_content_drafts, :status
  end
end
