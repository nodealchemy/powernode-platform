# frozen_string_literal: true

module Ai
  class FileLock < ApplicationRecord
    self.table_name = "ai_file_locks"

    LOCK_TYPES = %w[exclusive shared].freeze

    belongs_to :worktree_session, class_name: "Ai::WorktreeSession", foreign_key: "worktree_session_id"
    belongs_to :worktree, class_name: "Ai::Worktree", foreign_key: "worktree_id"
    belongs_to :account

    validates :file_path, presence: true, uniqueness: { scope: :worktree_session_id }
    validates :lock_type, inclusion: { in: LOCK_TYPES }

    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :for_session, ->(session_id) { where(worktree_session_id: session_id) }
    scope :for_file, ->(file_path) { where(file_path: file_path) }
    scope :exclusive_locks, -> { where(lock_type: "exclusive") }

    def expired?
      expires_at.present? && expires_at < Time.current
    end

    def active?
      !expired?
    end
  end
end
