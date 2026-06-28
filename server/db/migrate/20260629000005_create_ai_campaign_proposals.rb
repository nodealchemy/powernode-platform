# frozen_string_literal: true

# CampaignProposal queue (Campaign Discovery & Delegation Control Plane, increment 1):
# a durable, deduped queue of PROPOSED campaigns fed by continual discovery and manual
# entry. Reviewable/approvable in the frontend; an approved proposal spawns an
# Ai::Campaign (increment 3) and is back-linked via spawned_campaign_id.
class CreateAiCampaignProposals < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_campaign_proposals, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :spawned_campaign_id          # back-link to the Ai::Campaign this proposal became
      t.uuid :reviewed_by_id               # User who approved/rejected

      t.string :title, null: false
      t.text   :objective, null: false
      t.string :source, null: false, default: "manual"      # discovery|trajectory|improvement|manual
      t.string :scope                                        # optional target/repo scope label
      t.string :suggested_workload, null: false, default: "improvement-campaign"
      t.string :suggested_driver                             # claude_code|platform_agent|platform_group|platform_mission
      t.string :decision_authority, null: false, default: "trusted"
      t.string :fingerprint, null: false                     # per-target dedupe key (account-scoped)
      t.string :status, null: false, default: "proposed"     # proposed|queued|approved|rejected|spawned

      t.jsonb :configuration, null: false, default: {}       # spawn configuration (objective/scope/posture/...)
      t.jsonb :evidence, null: false, default: {}            # discovery evidence/links

      t.text :rejection_reason
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :ai_campaign_proposals, %i[account_id fingerprint], unique: true
    add_index :ai_campaign_proposals, %i[account_id status]
    add_index :ai_campaign_proposals, :account_id
    add_index :ai_campaign_proposals, :spawned_campaign_id
  end
end
