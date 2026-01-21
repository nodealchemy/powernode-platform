# frozen_string_literal: true

module SupplyChain
  class RemediationPlan < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_remediation_plans"

    # ============================================
    # Constants
    # ============================================
    PLAN_TYPES = %w[manual ai_generated auto_fix].freeze
    STATUSES = %w[draft pending_review approved rejected executing completed failed].freeze
    APPROVAL_STATUSES = %w[pending approved rejected].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :sbom, class_name: "SupplyChain::Sbom"
    belongs_to :workflow_run, class_name: "AiWorkflowRun", optional: true
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :approved_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :plan_type, presence: true, inclusion: { in: PLAN_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :confidence_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

    # ============================================
    # Scopes
    # ============================================
    scope :by_status, ->(status) { where(status: status) }
    scope :draft, -> { where(status: "draft") }
    scope :pending_review, -> { where(status: "pending_review") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :executing, -> { where(status: "executing") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :actionable, -> { where(status: %w[draft pending_review approved]) }
    scope :ai_generated, -> { where(plan_type: "ai_generated") }
    scope :auto_executable, -> { where(auto_executable: true) }
    scope :high_confidence, -> { where("confidence_score >= ?", 0.8) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def draft?
      status == "draft"
    end

    def pending_review?
      status == "pending_review"
    end

    def approved?
      status == "approved"
    end

    def rejected?
      status == "rejected"
    end

    def executing?
      status == "executing"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def manual?
      plan_type == "manual"
    end

    def ai_generated?
      plan_type == "ai_generated"
    end

    def auto_fix?
      plan_type == "auto_fix"
    end

    def can_execute?
      approved? && (auto_executable? || manual?)
    end

    def high_confidence?
      confidence_score.present? && confidence_score >= 0.8
    end

    def has_breaking_changes?
      breaking_changes.present? && breaking_changes.any?
    end

    def target_vulnerability_count
      target_vulnerabilities&.length || 0
    end

    def upgrade_count
      upgrade_recommendations&.length || 0
    end

    def submit_for_review!
      update!(status: "pending_review")
    end

    def approve!(user)
      update!(
        status: "approved",
        approval_status: "approved",
        approved_by: user,
        approved_at: Time.current
      )
    end

    def reject!(user, reason = nil)
      update!(
        status: "rejected",
        approval_status: "rejected",
        approved_by: user,
        approved_at: Time.current,
        metadata: metadata.merge("rejection_reason" => reason)
      )
    end

    def start_execution!
      update!(status: "executing")
    end

    def complete_execution!(pr_url = nil)
      attrs = { status: "completed" }
      attrs[:generated_pr_url] = pr_url if pr_url.present?
      update!(attrs)
    end

    def fail_execution!(error_message)
      update!(
        status: "failed",
        metadata: metadata.merge("execution_error" => error_message)
      )
    end

    def add_upgrade_recommendation(package_name:, current_version:, target_version:, reason: nil, breaking: false)
      rec = {
        package_name: package_name,
        current_version: current_version,
        target_version: target_version,
        reason: reason,
        is_breaking: breaking,
        added_at: Time.current.iso8601
      }

      self.upgrade_recommendations = (upgrade_recommendations || []) << rec

      if breaking
        self.breaking_changes = (breaking_changes || []) << {
          package_name: package_name,
          from_version: current_version,
          to_version: target_version,
          description: reason
        }
      end

      save!
    end

    def summary
      {
        id: id,
        plan_type: plan_type,
        status: status,
        target_vulnerability_count: target_vulnerability_count,
        upgrade_count: upgrade_count,
        has_breaking_changes: has_breaking_changes?,
        confidence_score: confidence_score,
        auto_executable: auto_executable,
        approval_status: approval_status,
        generated_pr_url: generated_pr_url,
        created_at: created_at
      }
    end

    def detailed_plan
      {
        summary: summary,
        sbom: sbom.summary,
        target_vulnerabilities: target_vulnerabilities,
        upgrade_recommendations: upgrade_recommendations,
        breaking_changes: breaking_changes,
        execution_summary: self.summary
      }
    end

    private

    def sanitize_jsonb_fields
      self.target_vulnerabilities ||= []
      self.upgrade_recommendations ||= []
      self.breaking_changes ||= []
      self.metadata ||= {}
    end
  end
end
