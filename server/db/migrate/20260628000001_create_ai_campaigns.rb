# frozen_string_literal: true

# Autonomous Improvement Campaigns — a first-class wrapper around the dev-improve Ralph loop.
# A Campaign owns its durable config (scope/posture/ordering/decision-authority/stop-conditions),
# a decision log, an async parked-questions queue, a progress ledger, and the Ralph loops it drives.
class CreateAiCampaigns < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_campaigns, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :created_by_id # User who started it (optional)
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "created" # created|active|paused|completed|archived

      # Durable configuration (replaces the hand-authored standing prompt):
      #   posture:        { stage_only:, branch:, remotes:, test_commands:, factories_note: }
      #   scope:          { repositories:[], trees:[] }
      #   ordering:       ordered list / policy for draining
      #   decision_authority: supervised|monitored|trusted|autonomous
      #   keep_going:     { refill_from_backlog:, batch_size: }
      #   stop_conditions:{ max_failed:, on_empty:, operator_review: }
      t.jsonb :configuration, null: false, default: {}
      t.string :decision_authority, null: false, default: "supervised"
      t.jsonb :stop_conditions, null: false, default: {}

      # Lifecycle
      t.datetime :started_at
      t.datetime :paused_at
      t.string :paused_reason
      t.datetime :completed_at
      t.text :completion_summary

      # Denormalized progress aggregates (latest snapshot)
      t.integer :loop_count, null: false, default: 0
      t.integer :total_tasks, null: false, default: 0
      t.integer :completed_tasks, null: false, default: 0
      t.integer :failed_tasks, null: false, default: 0
      t.integer :blocked_tasks, null: false, default: 0
      t.integer :open_questions, null: false, default: 0

      t.timestamps
    end
    add_index :ai_campaigns, [:account_id, :status]
    add_index :ai_campaigns, :account_id

    # Link Ralph loops to the campaign that drives them (optional — standalone loops keep working).
    add_column :ai_ralph_loops, :campaign_id, :uuid
    add_index :ai_ralph_loops, :campaign_id

    # Decision log — every operator/agent disposition of a fork or blocked task.
    create_table :ai_campaign_decisions, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :campaign_id, null: false
      t.uuid :ralph_task_id # the task it concerns (optional)
      t.uuid :user_id       # who decided (optional — agent decisions allowed)
      t.string :decision_type, null: false # unblock|skip|build|remove|defer|policy|escalate
      t.string :title
      t.text :rationale
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :ai_campaign_decisions, [:campaign_id, :created_at]
    add_index :ai_campaign_decisions, :ralph_task_id

    # Parked-questions queue — things the campaign cannot decide (live creds / policy value).
    # The operator answers asynchronously; the answer can resume a blocked task.
    create_table :ai_parked_questions, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :campaign_id, null: false
      t.uuid :ralph_task_id
      t.string :question, null: false
      t.text :context
      t.string :status, null: false, default: "open" # open|answered|dismissed
      t.text :answer
      t.uuid :answered_by_id
      t.datetime :answered_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :ai_parked_questions, [:campaign_id, :status]
    add_index :ai_parked_questions, :ralph_task_id

    # Progress ledger — periodic snapshots for the dashboard + trend.
    create_table :ai_progress_entries, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :campaign_id, null: false
      t.datetime :recorded_at, null: false
      t.integer :total_tasks, null: false, default: 0
      t.integer :completed_tasks, null: false, default: 0
      t.integer :failed_tasks, null: false, default: 0
      t.integer :blocked_tasks, null: false, default: 0
      t.decimal :completion_pct, precision: 5, scale: 2, default: "0.0"
      t.jsonb :per_loop_summary, null: false, default: {}
      t.jsonb :improvement_metrics, null: false, default: {} # net velocity, durable/reverted per-kind
      t.timestamps
    end
    add_index :ai_progress_entries, [:campaign_id, :recorded_at]
  end
end
