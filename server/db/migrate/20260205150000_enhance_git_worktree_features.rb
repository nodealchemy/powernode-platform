# frozen_string_literal: true

class EnhanceGitWorktreeFeatures < ActiveRecord::Migration[8.0]
  def change
    # =================================================================
    # File-level locking - prevents agents editing same files
    # =================================================================
    create_table :ai_file_locks, id: :uuid do |t|
      t.references :worktree_session, foreign_key: { to_table: :ai_worktree_sessions }, type: :uuid, index: true
      t.references :worktree, foreign_key: { to_table: :ai_worktrees }, type: :uuid, index: true
      t.references :account, foreign_key: true, type: :uuid
      t.string :file_path, null: false
      t.string :lock_type, null: false, default: "exclusive"
      t.datetime :acquired_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :ai_file_locks, [:worktree_session_id, :file_path], unique: true, name: "idx_ai_file_locks_session_file"

    # =================================================================
    # Cost/token tracking + timeout + test status on worktrees
    # =================================================================
    add_column :ai_worktrees, :tokens_used, :integer, default: 0
    add_column :ai_worktrees, :estimated_cost_cents, :integer, default: 0
    add_column :ai_worktrees, :timeout_at, :datetime
    add_column :ai_worktrees, :test_status, :string

    # =================================================================
    # Session enhancements - execution mode, timeout, conflict matrix
    # =================================================================
    add_column :ai_worktree_sessions, :execution_mode, :string, default: "complementary"
    add_column :ai_worktree_sessions, :max_duration_seconds, :integer
    add_column :ai_worktree_sessions, :conflict_matrix, :jsonb, default: {}
  end
end
