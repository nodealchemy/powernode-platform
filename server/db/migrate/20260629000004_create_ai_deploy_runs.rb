# frozen_string_literal: true

# Durable record of a deploy attempt produced by Ai::Deploy::Orchestrator — one per
# deploy of a target (platform-self or a project) via a method (workload/docker/
# kubernetes/sudo_bridge). Tracks the safety-envelope outcome: dry-run vs real,
# migration-safety verdict, executed/intended commands, health + rollback.
class CreateAiDeployRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_deploy_runs, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :campaign_id            # campaign whose land triggered this (optional)
      t.uuid :campaign_land_id       # the land that triggered it (optional)
      t.uuid :repository_id          # Devops::GitRepository for project deploys (optional)
      t.uuid :triggered_by_id        # user

      t.string :target_kind, null: false            # platform_self | project
      t.string :environment, null: false, default: "production"
      t.string :method_key, null: false             # workload | docker | kubernetes | sudo_bridge
      t.string :ref                                  # deployed sha/ref
      t.string :base_ref                             # previously-deployed ref (migration-safety + rollback)

      t.string :status, null: false, default: "pending" # pending running dry_run succeeded failed rolled_back skipped blocked
      t.boolean :dry_run, null: false, default: true

      t.text :detail
      t.jsonb :commands, null: false, default: []    # commands the method ran (or would, in dry-run)
      t.jsonb :metadata, null: false, default: {}
      t.text :error_message

      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :ai_deploy_runs, %i[account_id status]
    add_index :ai_deploy_runs, :account_id
    add_index :ai_deploy_runs, :campaign_land_id
    add_index :ai_deploy_runs, :repository_id
  end
end
