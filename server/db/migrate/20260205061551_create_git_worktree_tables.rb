# frozen_string_literal: true

class CreateGitWorktreeTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # ai_worktree_sessions - Tracks parallel execution sessions
    # ==========================================================================
    create_table :ai_worktree_sessions, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, index: true, null: false
      t.references :initiated_by, foreign_key: { to_table: :users }, type: :uuid
      t.references :source, polymorphic: true, type: :uuid, index: true

      t.string :repository_path, null: false
      t.string :base_branch, null: false, default: "main"
      t.string :integration_branch
      t.string :status, null: false, default: "pending"
      t.integer :max_parallel, null: false, default: 4
      t.integer :total_worktrees, null: false, default: 0
      t.integer :completed_worktrees, null: false, default: 0
      t.integer :failed_worktrees, null: false, default: 0
      t.string :merge_strategy, null: false, default: "sequential"
      t.jsonb :merge_config, null: false, default: {}
      t.boolean :auto_cleanup, null: false, default: true

      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      t.text :error_message
      t.string :error_code
      t.jsonb :error_details, null: false, default: {}

      t.jsonb :configuration, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ai_worktree_sessions, :status

    # ==========================================================================
    # ai_worktrees - Individual worktree records
    # ==========================================================================
    create_table :ai_worktrees, id: :uuid do |t|
      t.references :worktree_session, foreign_key: { to_table: :ai_worktree_sessions }, type: :uuid, index: true, null: false
      t.references :account, foreign_key: true, type: :uuid, null: false
      t.references :ai_agent, foreign_key: true, type: :uuid, index: true
      t.references :assignee, polymorphic: true, type: :uuid, index: true

      t.string :branch_name, null: false
      t.string :worktree_path, null: false
      t.string :base_commit_sha
      t.string :head_commit_sha
      t.integer :commit_count, null: false, default: 0
      t.string :status, null: false, default: "pending"

      t.boolean :locked, null: false, default: false
      t.string :lock_reason
      t.datetime :locked_at

      t.datetime :last_health_check_at
      t.boolean :healthy, null: false, default: true
      t.string :health_message

      t.jsonb :copied_config_files, null: false, default: []

      t.bigint :disk_usage_bytes
      t.integer :files_changed, null: false, default: 0
      t.integer :lines_added, null: false, default: 0
      t.integer :lines_removed, null: false, default: 0

      t.datetime :ready_at
      t.datetime :completed_at
      t.integer :duration_ms

      t.text :error_message
      t.string :error_code

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ai_worktrees, :branch_name, unique: true
    add_index :ai_worktrees, :worktree_path, unique: true
    add_index :ai_worktrees, :status

    # ==========================================================================
    # ai_merge_operations - Tracks merge attempts
    # ==========================================================================
    create_table :ai_merge_operations, id: :uuid do |t|
      t.references :worktree_session, foreign_key: { to_table: :ai_worktree_sessions }, type: :uuid, index: true, null: false
      t.references :worktree, foreign_key: { to_table: :ai_worktrees }, type: :uuid, index: true, null: false
      t.references :account, foreign_key: true, type: :uuid, null: false

      t.string :source_branch, null: false
      t.string :target_branch, null: false
      t.string :merge_commit_sha
      t.string :strategy, null: false, default: "merge"
      t.string :status, null: false, default: "pending"
      t.integer :merge_order

      t.boolean :has_conflicts, null: false, default: false
      t.jsonb :conflict_files, null: false, default: []
      t.text :conflict_details
      t.string :conflict_resolution

      t.string :pull_request_url
      t.string :pull_request_id
      t.string :pull_request_status

      t.string :rollback_commit_sha
      t.boolean :rolled_back, null: false, default: false
      t.datetime :rolled_back_at

      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      t.text :error_message
      t.string :error_code

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ai_merge_operations, :status

    # ==========================================================================
    # Add parallel_mode to ai_agent_teams
    # ==========================================================================
    add_column :ai_agent_teams, :parallel_mode, :string, default: "standard"
  end
end
