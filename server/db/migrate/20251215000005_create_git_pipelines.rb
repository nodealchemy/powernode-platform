# frozen_string_literal: true

class CreateGitPipelines < ActiveRecord::Migration[8.0]
  def change
    create_table :git_pipelines, id: :uuid do |t|
      t.references :git_repository, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :external_id, null: false, limit: 255
      t.string :name, null: false, limit: 255
      t.string :status, null: false, limit: 30
      t.string :conclusion, limit: 30
      t.string :trigger_event, limit: 50
      t.string :ref, limit: 500
      t.string :sha, limit: 64
      t.string :head_sha, limit: 64
      t.string :actor_username, limit: 255
      t.string :actor_id, limit: 255
      t.string :web_url, limit: 500
      t.string :logs_url, limit: 500
      t.integer :run_number
      t.integer :run_attempt, default: 1
      t.integer :total_jobs, default: 0
      t.integer :completed_jobs, default: 0
      t.integer :failed_jobs, default: 0
      t.integer :duration_seconds
      t.jsonb :workflow_config, default: {}
      t.jsonb :metadata, default: {}
      t.timestamp :started_at
      t.timestamp :completed_at

      t.timestamps
    end

    add_index :git_pipelines, %i[git_repository_id external_id], unique: true
    add_index :git_pipelines, :status
    add_index :git_pipelines, :conclusion
    add_index :git_pipelines, :trigger_event
    add_index :git_pipelines, :sha
    add_index :git_pipelines, %i[account_id created_at]
    add_index :git_pipelines, :created_at
  end
end
