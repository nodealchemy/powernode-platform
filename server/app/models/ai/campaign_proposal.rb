# frozen_string_literal: true

module Ai
  # A durable, deduped QUEUE of proposed campaigns (Campaign Discovery & Delegation
  # Control Plane). Proposals are fed by continual discovery (increment 2) or created
  # manually, reviewed/approved in the frontend, and spawned into an Ai::Campaign
  # (increment 3) that can be delegated to a Claude Code dev-loop or a platform
  # agent/group/mission (increment 4). Dedupe is per-target within an account
  # (improvement-fingerprint-per-target): re-discovering the same gap refreshes the
  # open proposal instead of enqueuing a duplicate, and never resurrects one the
  # operator has already decided (rejected/spawned).
  class CampaignProposal < ApplicationRecord
    STATUSES = %w[proposed queued approved rejected spawned].freeze
    # Terminal = the operator already decided; a rediscovery must not resurrect it.
    TERMINAL_STATUSES = %w[rejected spawned].freeze
    SOURCES = %w[discovery trajectory improvement manual].freeze
    # Editable via #update_fields! — only while status is proposed/queued (pre-approval).
    UPDATABLE_FIELDS = %i[title objective source scope suggested_workload suggested_driver
                          decision_authority configuration].freeze
    PRE_APPROVAL_STATUSES = %w[proposed queued].freeze
    # Where an approved proposal's campaign loop can be delegated to drain (increment 4).
    SUGGESTED_DRIVERS = %w[claude_code platform_agent platform_team platform_mission].freeze
    # Workloads mirror the campaign driver's — a proposal spawns one of these.
    WORKLOADS = Ai::DevLoop::CampaignDriver::WORKLOADS
    DEFAULT_WORKLOAD = Ai::DevLoop::CampaignDriver::DEFAULT_WORKLOAD

    belongs_to :account
    belongs_to :spawned_campaign, class_name: "Ai::Campaign", optional: true
    belongs_to :reviewed_by, class_name: "User", optional: true

    validates :title, presence: true, length: { maximum: 255 }
    validates :objective, presence: true, length: { maximum: 5_000 }
    validates :source, presence: true, inclusion: { in: SOURCES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :suggested_workload, presence: true, inclusion: { in: WORKLOADS }
    validates :suggested_driver, inclusion: { in: SUGGESTED_DRIVERS }, allow_blank: true
    validates :decision_authority, presence: true, inclusion: { in: Ai::Campaign::DECISION_AUTHORITY }
    validates :fingerprint, presence: true, uniqueness: { scope: :account_id }

    before_validation :ensure_fingerprint

    scope :proposed, -> { where(status: "proposed") }
    scope :queued, -> { where(status: "queued") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :spawned, -> { where(status: "spawned") }
    scope :open, -> { where.not(status: TERMINAL_STATUSES) }     # proposed|queued|approved
    scope :actionable, -> { where(status: %w[queued approved]) }
    scope :by_status, ->(status) { where(status: status) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }

    # Stable per-target dedupe fingerprint. Target = (scope, objective, workload) within
    # an account — re-discovering the same gap yields the same fingerprint regardless of
    # whitespace/case in the objective.
    def self.fingerprint_for(scope:, objective:, suggested_workload: nil)
      norm = [
        scope.to_s.strip.downcase,
        objective.to_s.strip.downcase.gsub(/\s+/, " "),
        suggested_workload.to_s.strip.downcase
      ].join("|")
      Digest::SHA256.hexdigest(norm)
    end

    # Idempotently enqueue a proposal. A terminal duplicate (rejected/spawned) is left
    # as-is (the operator already decided). An open duplicate is refreshed with the
    # latest discovery fields. Otherwise a new `proposed` row is created. Returns the
    # proposal in all cases.
    def self.propose!(account:, title:, objective:, source: "manual", scope: nil,
                      suggested_workload: nil, suggested_driver: nil,
                      decision_authority: "trusted", configuration: {}, evidence: {})
      workload = suggested_workload.presence || DEFAULT_WORKLOAD
      fp = fingerprint_for(scope: scope, objective: objective, suggested_workload: workload)
      existing = account.ai_campaign_proposals.find_by(fingerprint: fp)
      if existing
        return existing if existing.terminal?

        existing.update!(
          title: title, objective: objective, source: source, scope: scope,
          suggested_workload: workload, suggested_driver: suggested_driver,
          configuration: configuration || {}, evidence: evidence || {}
        )
        return existing
      end

      account.ai_campaign_proposals.create!(
        title: title, objective: objective, source: source, scope: scope,
        suggested_workload: workload, suggested_driver: suggested_driver,
        decision_authority: decision_authority, configuration: configuration || {},
        evidence: evidence || {}, fingerprint: fp, status: "proposed"
      )
    rescue ActiveRecord::RecordNotUnique
      # TOCTOU: a concurrent propose! (e.g. discovery cron vs manual create) won the
      # (account_id, fingerprint) unique index between our find_by and create!. Converge
      # to the existing row instead of surfacing a 500.
      account.ai_campaign_proposals.find_by!(fingerprint: fp)
    end

    def queue!
      update!(status: "queued")
    end

    # Revise a proposal's fields before it's been approved (operator-directed review
    # rounds, as opposed to .propose!'s discovery-rediscovery refresh path above).
    # Recomputes the fingerprint so dedupe stays consistent with the edited target.
    def update_fields!(**attrs)
      unless PRE_APPROVAL_STATUSES.include?(status)
        raise ArgumentError, "cannot update a #{status} proposal — only proposed/queued proposals can be edited"
      end

      attrs = attrs.slice(*UPDATABLE_FIELDS).compact
      return self if attrs.empty?

      attrs[:fingerprint] = self.class.fingerprint_for(
        scope: attrs.fetch(:scope, scope),
        objective: attrs.fetch(:objective, objective),
        suggested_workload: attrs.fetch(:suggested_workload, suggested_workload)
      )
      update!(attrs)
      self
    end

    def approve!(user = nil)
      update!(status: "approved", reviewed_by: user, reviewed_at: Time.current)
    end

    def reject!(user = nil, reason: nil)
      update!(status: "rejected", reviewed_by: user, reviewed_at: Time.current, rejection_reason: reason)
    end

    # Back-link the spawned campaign (called by increment 3 after CampaignDriver#start).
    def mark_spawned!(campaign)
      update!(status: "spawned", spawned_campaign: campaign)
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def open?
      !terminal?
    end

    # Args for Ai::DevLoop::CampaignDriver#start (increment 3 consumes this).
    def to_campaign_args
      {
        name: title,
        description: objective,
        configuration: (configuration || {}).deep_dup,
        decision_authority: decision_authority,
        workload: suggested_workload
      }
    end

    def summary
      {
        id: id, title: title, objective: objective, source: source, scope: scope,
        status: status, suggested_workload: suggested_workload, suggested_driver: suggested_driver,
        decision_authority: decision_authority, fingerprint: fingerprint,
        spawned_campaign_id: spawned_campaign_id, reviewed_by_id: reviewed_by_id,
        reviewed_at: reviewed_at, rejection_reason: rejection_reason,
        created_at: created_at, updated_at: updated_at
      }
    end

    private

    def ensure_fingerprint
      return if fingerprint.present?

      self.fingerprint = self.class.fingerprint_for(
        scope: scope, objective: objective, suggested_workload: suggested_workload
      )
    end
  end
end
