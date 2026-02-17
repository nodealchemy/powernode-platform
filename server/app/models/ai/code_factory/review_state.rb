# frozen_string_literal: true

module Ai
  module CodeFactory
    class ReviewState < ApplicationRecord
      self.table_name = "ai_code_factory_review_states"

      STATUSES = %w[pending reviewing clean dirty stale].freeze

      belongs_to :account
      belongs_to :risk_contract, class_name: "Ai::CodeFactory::RiskContract", foreign_key: "risk_contract_id"
      belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "repository_id", optional: true

      has_many :evidence_manifests, class_name: "Ai::CodeFactory::EvidenceManifest",
               foreign_key: "review_state_id", dependent: :destroy

      validates :pr_number, presence: true
      validates :head_sha, presence: true
      validates :status, presence: true, inclusion: { in: STATUSES }

      scope :for_pr, ->(pr_number) { where(pr_number: pr_number) }
      scope :current, -> { where.not(status: "stale") }
      scope :pending, -> { where(status: "pending") }
      scope :clean, -> { where(status: "clean") }
      scope :dirty, -> { where(status: "dirty") }
      scope :stale, -> { where(status: "stale") }
      scope :recent, -> { order(created_at: :desc) }

      before_validation :set_defaults, on: :create

      def sha_current?(sha)
        head_sha == sha
      end

      def mark_stale!(reason = nil)
        update!(status: "stale", stale_reason: reason)
      end

      def mark_reviewing!
        update!(status: "reviewing")
      end

      def mark_clean!
        update!(status: "clean", reviewed_at: Time.current, all_checks_passed: true)
      end

      def mark_dirty!(findings_count: 0, critical_count: 0)
        update!(
          status: "dirty",
          reviewed_at: Time.current,
          review_findings_count: findings_count,
          critical_findings_count: critical_count,
          all_checks_passed: false
        )
      end

      def record_check_completion!(check_name)
        completed = completed_checks || []
        return if completed.include?(check_name)

        completed << check_name
        update!(completed_checks: completed)

        if required_checks.present? && (required_checks - completed).empty?
          update!(all_checks_passed: true)
        end
      end

      def merge_ready?
        status == "clean" && all_checks_passed? && (!evidence_required? || evidence_verified?)
      end

      def evidence_required?
        risk_contract&.evidence_requirements.present? &&
          risk_contract.evidence_requirements["required"] == true
      end

      private

      def set_defaults
        self.status ||= "pending"
        self.required_checks ||= []
        self.completed_checks ||= []
        self.metadata ||= {}
      end
    end
  end
end
