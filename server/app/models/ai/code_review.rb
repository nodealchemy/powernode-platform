# frozen_string_literal: true

module Ai
  class CodeReview < ApplicationRecord
    self.table_name = "ai_code_reviews"

    # Associations
    belongs_to :account
    belongs_to :pipeline_execution, class_name: "Ai::PipelineExecution", foreign_key: "pipeline_execution_id", optional: true

    # Validations
    validates :review_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: %w[pending analyzing completed failed partial] }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :analyzing, -> { where(status: "analyzing") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :for_repository, ->(repo_id) { where(repository_id: repo_id) }
    scope :for_pr, ->(pr_number) { where(pull_request_number: pr_number) }
    scope :with_critical_issues, -> { where("critical_issues > 0") }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :set_review_id, on: :create

    # Methods
    def pending?
      status == "pending"
    end

    def analyzing?
      status == "analyzing"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def start_analysis!
      update!(status: "analyzing", started_at: Time.current)
    end

    def complete!(file_analyses:, issues:, suggestions:, security_findings: [], quality_metrics: {}, summary: nil, overall_rating: nil, tokens_used: 0, cost: 0)
      update!(
        status: "completed",
        completed_at: Time.current,
        files_reviewed: file_analyses.length,
        file_analyses: file_analyses,
        issues: issues,
        issues_found: issues.length,
        critical_issues: issues.count { |i| i["severity"] == "critical" },
        suggestions: suggestions,
        suggestions_count: suggestions.length,
        security_findings: security_findings,
        quality_metrics: quality_metrics,
        summary: summary,
        overall_rating: overall_rating,
        tokens_used: tokens_used,
        cost_usd: cost
      )
    end

    def fail!(error_message = nil)
      update!(
        status: "failed",
        completed_at: Time.current,
        summary: error_message
      )
    end

    def has_critical_issues?
      critical_issues.to_i > 0
    end

    def has_security_findings?
      security_findings.present? && security_findings.any?
    end

    def approval_recommendation
      return "block" if critical_issues.to_i > 0
      return "caution" if issues_found.to_i > 5 || has_security_findings?
      return "approve" if issues_found.to_i == 0

      "review"
    end

    def code_quality_score
      return nil unless quality_metrics.present?

      scores = []
      scores << quality_metrics["maintainability"] if quality_metrics["maintainability"]
      scores << quality_metrics["reliability"] if quality_metrics["reliability"]
      scores << quality_metrics["security"] if quality_metrics["security"]

      return nil if scores.empty?

      (scores.sum / scores.length).round(1)
    end

    private

    def set_review_id
      self.review_id ||= SecureRandom.uuid
    end
  end
end
