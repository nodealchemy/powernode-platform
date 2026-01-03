# frozen_string_literal: true

class CreateGitRunners < ActiveRecord::Migration[8.0]
  def change
    create_table :git_runners, id: :uuid do |t|
      t.references :git_provider_credential, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :git_repository, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.string :external_id, null: false
      t.string :name, null: false
      t.string :runner_scope, null: false, default: 'repository'
      t.string :status, null: false, default: 'offline'
      t.boolean :busy, null: false, default: false
      t.jsonb :labels, null: false, default: []
      t.string :os
      t.string :architecture
      t.string :version
      t.integer :total_jobs_run, null: false, default: 0
      t.integer :successful_jobs, null: false, default: 0
      t.integer :failed_jobs, null: false, default: 0
      t.timestamp :last_seen_at

      t.timestamps
    end

    add_index :git_runners, [:git_provider_credential_id, :external_id], unique: true, name: 'idx_git_runners_on_credential_and_external_id'
    add_index :git_runners, :status
    add_index :git_runners, :runner_scope
    add_index :git_runners, :busy
    add_index :git_runners, :last_seen_at
  end
end
