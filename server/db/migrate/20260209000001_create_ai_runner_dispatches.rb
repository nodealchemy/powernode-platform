# frozen_string_literal: true

class CreateAiRunnerDispatches < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_runner_dispatches, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, index: true
      t.references :worktree_session, type: :uuid, foreign_key: { to_table: :ai_worktree_sessions }, index: true
      t.references :worktree, type: :uuid, foreign_key: { to_table: :ai_worktrees }
      t.references :git_runner, type: :uuid, foreign_key: { to_table: :git_runners }
      t.references :git_repository, type: :uuid, foreign_key: { to_table: :git_repositories }
      t.string :workflow_run_id
      t.string :workflow_url
      t.string :status, default: "pending"
      t.jsonb :input_params, default: {}
      t.jsonb :output_result, default: {}
      t.jsonb :runner_labels, default: []
      t.text :logs
      t.datetime :dispatched_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.timestamps
    end
  end
end
