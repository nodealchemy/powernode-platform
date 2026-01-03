# frozen_string_literal: true

class CreateGitPipelineJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :git_pipeline_jobs, id: :uuid do |t|
      t.references :git_pipeline, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :external_id, null: false, limit: 255
      t.string :name, null: false, limit: 255
      t.string :status, null: false, limit: 30
      t.string :conclusion, limit: 30
      t.integer :step_number
      t.string :runner_name, limit: 255
      t.string :runner_id, limit: 255
      t.string :runner_os, limit: 50
      t.text :logs_url
      t.text :logs_content
      t.integer :duration_seconds
      t.jsonb :steps, default: []
      t.jsonb :outputs, default: {}
      t.jsonb :metadata, default: {}
      t.timestamp :started_at
      t.timestamp :completed_at

      t.timestamps
    end

    add_index :git_pipeline_jobs, %i[git_pipeline_id external_id], unique: true
    add_index :git_pipeline_jobs, :status
    add_index :git_pipeline_jobs, :conclusion
    add_index :git_pipeline_jobs, :runner_name
    add_index :git_pipeline_jobs, %i[account_id created_at]
  end
end
