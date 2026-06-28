# frozen_string_literal: true

# Ai::CampaignLand — durable record + queue row + state machine for landing a
# campaign's staged change-set to a target branch (default develop) behind an
# approval gate + CI gate, reusing Ai::Git::MergeService. One row per land attempt.
class CreateAiCampaignLands < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_campaign_lands, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :campaign_id, null: false
      t.uuid :account_id, null: false

      # pending_approval|queued|staging|staged_ci|merging|verifying|rolling_back
      #   |landed|parked|rejected|rolled_back|failed
      t.string :status, null: false, default: "pending_approval"

      t.string :source_branch, null: false          # campaign/<id>
      t.string :staging_branch                       # land/<id> (rebased onto target)
      t.string :target_branch, null: false, default: "develop"

      t.string :base_sha                             # target HEAD the staging branch was rebased onto
      t.string :staged_sha                           # HEAD of staging branch (what CI gates)
      t.string :merged_sha                           # merge commit on target (what post-CI gates)

      t.uuid :worktree_session_id                    # session built for MergeService reuse
      t.uuid :merge_operation_id                     # for rollback
      t.uuid :pre_ci_pipeline_id                     # Devops::GitPipeline on staged branch
      t.uuid :post_ci_pipeline_id                    # Devops::GitPipeline on target@merged_sha

      t.jsonb :conflict_files, null: false, default: []
      t.text :parked_reason
      t.text :error_message
      t.integer :priority, null: false, default: 0   # queue ordering (higher first)

      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :parked_at

      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ai_campaign_lands, [:account_id, :status]
    add_index :ai_campaign_lands, [:target_branch, :status]
    add_index :ai_campaign_lands, :campaign_id
  end
end
