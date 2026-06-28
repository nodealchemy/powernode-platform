# frozen_string_literal: true

# Ai::Delivery — progressive-delivery layer on top of Ai::Deploy. A DeliveryRun records one
# delivery of a ref to a target via a strategy (direct | canary | blue_green): direct delegates
# to Ai::Deploy::Orchestrator (linked via deploy_run_id); canary/blue_green capture the staged
# rollout plan + step results. Mirrors ai_deploy_runs so the two compose cleanly.
class CreateAiDeliveryRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_delivery_runs, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :campaign_id            # campaign whose land triggered this (optional)
      t.uuid :campaign_land_id       # the land that triggered it (optional)
      t.uuid :repository_id          # Devops::GitRepository for project deliveries (optional)
      t.uuid :triggered_by_id        # user
      t.uuid :deploy_run_id          # the underlying Ai::DeployRun (direct strategy)

      t.string :target_kind, null: false              # platform_self | project
      t.string :environment, null: false, default: "production"
      t.string :strategy, null: false, default: "direct" # direct | canary | blue_green
      t.string :status, null: false, default: "pending" # pending running planned dry_run succeeded failed rolled_back
      t.boolean :dry_run, null: false, default: true
      t.string :ref                                    # delivered sha/ref
      t.string :base_ref                               # previously-delivered ref

      t.jsonb :steps, null: false, default: []         # progressive rollout plan + per-step results
      t.text :detail
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :ai_delivery_runs, %i[account_id status]
    add_index :ai_delivery_runs, :account_id
    add_index :ai_delivery_runs, :campaign_id
    add_index :ai_delivery_runs, :deploy_run_id
  end
end
