# frozen_string_literal: true

module Ai
  class CodeReviewComment < ApplicationRecord
    self.table_name = "ai_code_review_comments"

    # ==================== Constants ====================
    COMMENT_TYPES = %w[suggestion issue praise question].freeze
    SEVERITIES = %w[critical warning info].freeze

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :task_review, class_name: "Ai::TaskReview"
    belongs_to :agent, class_name: "Ai::Agent", optional: true

    # ==================== Validations ====================
    validates :file_path, presence: true
    validates :content, presence: true
    validates :comment_type, presence: true, inclusion: { in: COMMENT_TYPES }
    validates :severity, presence: true, inclusion: { in: SEVERITIES }

    # ==================== Scopes ====================
    scope :by_file, ->(path) { where(file_path: path) }
    scope :by_severity, ->(sev) { where(severity: sev) }
    scope :by_type, ->(type) { where(comment_type: type) }
    scope :unresolved, -> { where(resolved: false) }
    scope :resolved, -> { where(resolved: true) }
    scope :suggestions, -> { where(comment_type: "suggestion") }
    scope :issues, -> { where(comment_type: "issue") }
    scope :critical, -> { where(severity: "critical") }
    scope :ordered, -> { order(:file_path, :line_start) }

    # ==================== Instance Methods ====================

    def resolve!
      update!(resolved: true)
    end

    def unresolve!
      update!(resolved: false)
    end

    def comment_summary
      {
        id: id,
        file_path: file_path,
        line_start: line_start,
        line_end: line_end,
        comment_type: comment_type,
        severity: severity,
        content: content,
        suggested_fix: suggested_fix,
        category: category,
        resolved: resolved,
        agent_id: agent_id,
        created_at: created_at
      }
    end
  end
end
