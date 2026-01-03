# frozen_string_literal: true

class CreateGitPipelineSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :git_pipeline_schedules, id: :uuid do |t|
      t.references :git_repository, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }

      # Schedule Configuration
      t.string :name, null: false
      t.string :description
      t.string :cron_expression, null: false
      t.string :timezone, null: false, default: "UTC"
      t.string :ref, null: false  # Branch or tag to run on

      # Workflow Configuration
      t.string :workflow_file  # Specific workflow to trigger (optional)
      t.jsonb :inputs, null: false, default: {}  # Workflow inputs

      # State
      t.boolean :is_active, null: false, default: true
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.string :last_run_status  # success, failure, skipped

      # Metrics
      t.integer :run_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.integer :consecutive_failures, null: false, default: 0

      # Reference to last triggered pipeline
      t.references :last_pipeline, type: :uuid, foreign_key: { to_table: :git_pipelines, on_delete: :nullify }

      t.timestamps
    end

    add_index :git_pipeline_schedules, :is_active
    add_index :git_pipeline_schedules, :next_run_at
    add_index :git_pipeline_schedules, [ :git_repository_id, :name ], unique: true
  end
end
