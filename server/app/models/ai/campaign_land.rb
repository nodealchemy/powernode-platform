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
    # Routes through the governance ApprovalRequest when one is OPEN (resolving
    # it cascades back here via on_approval_decision), else acts directly — core
    # mode, or a request that has already been decided.
    #
    # The branch is keyed on `pending?`, not on the request's mere existence:
    # re-approving an already-approved row writes the same status, so no
    # after_update fires, no cascade arrives, and the land would sit in
    # pending_approval forever. `pending?` and not the `active` scope — a row
    # past expires_at that check_expiration! has not swept yet is still the open
    # gate, and routing it to the direct arm would re-create the dangling row
    # this exists to prevent. IMP-7836ec7a974d — this guard was
    # `respond_to?(:approve!)`, which is false for a private method, so the
    # governed arm never ran and the request was left dangling as `pending`.
    def operator_approve!(user: nil)
      req = approval_request
      if req&.pending?
        req.approve!
      elsif status == "pending_approval"
        enqueue!
      end
      reload
    end

    def operator_reject!(user: nil, reason: nil)
      req = approval_request
      if req&.pending?
        req.reject!
        # The cascade rejects this land with a generic "approval rejected";
        # keep the operator's own words so both arms record the same reason.
        reload
        update!(error_message: reason) if reason.present? && status == "rejected"
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

    # The "owner/repo" the worker should clone for the deep land security scan
    # (G4 worker depth). A land carries no repository column, so it is resolved
    # generically from the source's loops (each Ai::RalphLoop derives it from its
    # repository_url). Returns nil when no loop records one (e.g. a legacy land),
    # in which case the worker skips the deep scan cleanly.
    def repository_full_name
      source_ralph_loops.where.not(repository_url: [ nil, "" ]).find_each do |loop|
        name = loop.repository_full_name
        return name if name.present?
      end
      nil
    end

    # The loops that produced this land's change, resolved generically from the
    # source (campaign has_many :ralph_loops; a mission's loops point back via
    # mission_id).
    def source_ralph_loops
      src = source
      if src.respond_to?(:ralph_loops)
        src.ralph_loops
      elsif src.is_a?(::Ai::Mission)
        ::Ai::RalphLoop.where(mission_id: src.id)
      else
        ::Ai::RalphLoop.none
      end
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
        repository: repository_full_name,
        base_sha: base_sha, staged_sha: staged_sha, merged_sha: merged_sha,
        conflict_files: conflict_files, parked_reason: parked_reason, error_message: error_message,
        priority: priority, queued_at: queued_at, completed_at: completed_at
      }
    end
  end
end
