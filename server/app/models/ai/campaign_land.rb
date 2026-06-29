# frozen_string_literal: true

module Ai
  # A single attempt to land a campaign's staged change-set onto a target branch
  # (default develop) behind an approval + CI gate. Reuses Ai::Git::MergeService
  # for the actual merge/rollback; this model is the durable queue row + state
  # machine. Approval unblocks it via #on_approval_decision (mirrors
  # Ai::DeferredOperation), so it works with or without the governance extension.
  class CampaignLand < ApplicationRecord
    self.table_name = "ai_campaign_lands"

    STATUSES = %w[
      pending_approval queued staging staged_ci merging verifying rolling_back
      landed parked rejected rolled_back failed
    ].freeze
    # Phases that hold the per-target land slot (LandingQueue allows one at a time).
    ACTIVE_STATUSES = %w[staging staged_ci merging verifying rolling_back].freeze
    TERMINAL_STATUSES = %w[landed rejected rolled_back failed].freeze

    # Legacy direct pointer — retained (and still populated for campaign lands)
    # for back-compat with existing queries/indexes. Now optional so non-campaign
    # land sources (Missions, etc.) can leave it NULL.
    belongs_to :campaign, class_name: "Ai::Campaign", foreign_key: "campaign_id", optional: true
    # Canonical, generic land source. Campaign lands set BOTH this and campaign;
    # other landables (Ai::Mission, ...) set only this.
    belongs_to :source, polymorphic: true, optional: true
    belongs_to :account

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :source_branch, :target_branch, presence: true

    scope :awaiting_approval, -> { where(status: "pending_approval") }
    scope :queued, -> { where(status: "queued") }
    scope :active, -> { where(status: ACTIVE_STATUSES) }
    scope :active_for, ->(target) { active.where(target_branch: target) }
    scope :parked, -> { where(status: "parked") }
    scope :open, -> { where.not(status: TERMINAL_STATUSES) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }

    # ---- approval unblock seam (mirrors Ai::DeferredOperation#on_approval_decision)
    def on_approval_decision(request)
      return unless status == "pending_approval"

      case request.status
      when "approved" then enqueue!
      when "rejected" then reject!("approval rejected")
      when "expired"  then reject!("approval expired")
      end
    end

    # ---- operator decision (from the proposal card / dashboard) -----------
    # Routes through the governance ApprovalRequest when present (which cascades
    # back here via on_approval_decision), else acts directly (core mode).
    def operator_approve!(user: nil)
      req = approval_request
      if req&.respond_to?(:approve!)
        req.approve!
      elsif status == "pending_approval"
        enqueue!
      end
      reload
    end

    def operator_reject!(user: nil, reason: nil)
      req = approval_request
      if req&.respond_to?(:reject!)
        req.reject!
      elsif status == "pending_approval"
        reject!(reason || "rejected by operator")
      end
      reload
    end

    # ---- state machine ----------------------------------------------------
    def enqueue!
      update!(status: "queued", queued_at: queued_at || Time.current)
    end

    def begin_staging!
      update!(status: "staging", started_at: started_at || Time.current)
    end

    def mark_staged_ci!(staged_sha:, pre_ci_pipeline_id: nil)
      update!(status: "staged_ci", staged_sha: staged_sha, pre_ci_pipeline_id: pre_ci_pipeline_id)
    end

    def begin_merging!
      update!(status: "merging")
    end

    def begin_verifying!(merged_sha:, merge_operation_id: nil, post_ci_pipeline_id: nil)
      update!(status: "verifying", merged_sha: merged_sha,
              merge_operation_id: merge_operation_id, post_ci_pipeline_id: post_ci_pipeline_id)
    end

    def begin_rollback!
      update!(status: "rolling_back")
    end

    def land!
      update!(status: "landed", completed_at: Time.current)
    end

    def park!(reason:, files: [])
      update!(status: "parked", parked_reason: reason, conflict_files: files, parked_at: Time.current)
    end

    def reject!(reason = nil)
      update!(status: "rejected", error_message: reason, completed_at: Time.current)
    end

    def mark_rolled_back!
      update!(status: "rolled_back", completed_at: Time.current)
    end

    def fail!(message = nil)
      update!(status: "failed", error_message: message, completed_at: Time.current)
    end

    # ---- helpers ----------------------------------------------------------
    # Resolve the land source generically. Prefers the polymorphic association;
    # falls back to the legacy campaign pointer so rows written before the
    # source columns existed (and any campaign land) still resolve to a source.
    def source
      super || (campaign if campaign_id.present?)
    end

    def terminal?
      status.in?(TERMINAL_STATUSES)
    end

    def active?
      status.in?(ACTIVE_STATUSES)
    end

    # Latest approval request gating this land (governance extension only).
    def approval_request
      return nil unless defined?(::Ai::ApprovalRequest)

      ::Ai::ApprovalRequest.for_source("Ai::CampaignLand", id).order(created_at: :desc).first
    end

    def summary
      {
        id: id, campaign_id: campaign_id, source_type: source_type, source_id: source_id, status: status,
        source_branch: source_branch, staging_branch: staging_branch, target_branch: target_branch,
        base_sha: base_sha, staged_sha: staged_sha, merged_sha: merged_sha,
        conflict_files: conflict_files, parked_reason: parked_reason, error_message: error_message,
        priority: priority, queued_at: queued_at, completed_at: completed_at
      }
    end
  end
end
