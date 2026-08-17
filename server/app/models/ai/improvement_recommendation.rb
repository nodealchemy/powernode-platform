# frozen_string_literal: true

module Ai
  class ImprovementRecommendation < ApplicationRecord
    STATUSES = %w[pending approved applied dismissed].freeze
    RECOMMENDATION_TYPES = %w[provider_switch team_composition timeout_adjustment model_upgrade cost_optimization skill_consolidation skill_connection prompt_refinement skill_creation code_lint dead_code code_duplication convention_adherence test_gap agent_reliability skill_health learning_health capability_gap].freeze
    # Code-quality types are discovered via the /improve loop (Tier-1) and promoted
    # to dev-improve Ralph tasks rather than auto-applied as config changes.
    CODE_QUALITY_TYPES = %w[code_lint dead_code code_duplication convention_adherence test_gap].freeze

    belongs_to :account
    belongs_to :approved_by, class_name: "User", foreign_key: "approved_by_id", optional: true

    validates :recommendation_type, presence: true, inclusion: { in: RECOMMENDATION_TYPES }
    validates :target_type, presence: true
    validates :target_id, presence: true
    validates :confidence_score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: "pending") }
    scope :approved, -> { where(status: "approved") }
    scope :applied, -> { where(status: "applied") }
    scope :dismissed, -> { where(status: "dismissed") }
    scope :high_confidence, -> { where("confidence_score >= ?", 0.7) }
    scope :by_type, ->(type) { where(recommendation_type: type) }
    scope :for_target, ->(target_type, target_id) { where(target_type: target_type, target_id: target_id) }
    # Tier-2(b): first-class repository scoping via the polymorphic target
    scope :by_repository, ->(repository_id) { where(target_type: "Devops::GitRepository", target_id: repository_id) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }

    # Approval-unification (flag-gated): newly-created recommendations open a
    # governance ApprovalRequest so their approve/dismiss decision can flow
    # through Ai::Approvals::Gateway. Default OFF — no-op unless governance is
    # present AND the opt-in flag is set (see #open_approval_gate!).
    after_create :open_approval_gate!

    def approve!(user)
      update!(status: "approved", approved_by: user)
    end

    def apply!(user)
      update!(status: "applied", approved_by: user, applied_at: Time.current)
    end

    def dismiss!
      update!(status: "dismissed")
    end

    def target
      target_type.constantize.find_by(id: target_id)
    rescue NameError
      nil
    end

    # Approval-unification cascade target. Ai::ApprovalRequest#notify_source_of_decision
    # invokes this when a gateway-routed recommendation gate resolves. Approves
    # on approval, dismisses on rejection/expiry; no-op unless still pending,
    # guarding against stale or duplicate cascades.
    def on_approval_decision(request)
      return Ai::ApprovalRequest::DISPATCH_NOOP unless status == "pending"

      resolver = request.decisions.order(:created_at).last&.approver
      case request.status
      when "approved"
        approve!(resolver)
      when "rejected", "expired"
        dismiss!
      else
        return Ai::ApprovalRequest::DISPATCH_NOOP
      end

      Ai::ApprovalRequest::DISPATCH_EXECUTED
    end

    private

    # Best-effort, flag-gated opener for the governance ApprovalRequest. Default
    # OFF: requires a governance extension AND the account opt-in flag. Failures
    # are logged, never raised, so recommendation creation is never broken.
    def open_approval_gate!
      return unless Ai::Approvals::Gateway.governance_enabled? &&
                    account.settings&.dig("ai", "approvals_via_gateway")

      Ai::Approvals::Gateway.new(account: account).request!(
        approvable: self,
        kind: "improvement_recommendation",
        request_data: { recommendation_type: recommendation_type, target_type: target_type, target_id: target_id }
      )
    rescue StandardError => e
      Rails.logger.warn("[ImprovementRecommendation] open_approval_gate! failed for #{id}: #{e.class}: #{e.message}")
    end
  end
end
