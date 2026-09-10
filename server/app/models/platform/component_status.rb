# frozen_string_literal: true

module Platform
  # ONE row per component, upserted by Platform::Status::SweepService.
  #
  # A "component" is anything a contributor enumerates: an AI provider, a
  # docker host, a node instance, a certificate. The row carries the verdict,
  # the conditions the verdict was derived from, the edges to its neighbours,
  # and everything the operator page needs to render it WITHOUT knowing the
  # kind (display name, icon, links, actions). That is the point: core learns
  # nothing kind-specific, and a new kind is a new contributor file.
  #
  # THE VERDICT LADDER (design §4.1):
  #
  #   ok < held < progressing < not_measured < degraded < down
  #
  # - `held` is OPERATOR INTENT — cordoned, paused, drained, on hold. It is
  #   deliberately not a failure: a planned drain must never turn a header
  #   amber, which is why Platform::Status::Rollup computes the operational
  #   verdict EXCLUDING held and carries the held count beside it.
  # - `progressing` is an in-flight remediation or provisioning.
  # - `not_measured` is an ABSENT measurement. It ranks below `degraded`
  #   because a missing reading is a gap, not a failure — but it is never
  #   collapsed into `ok`. A thing we could not see is not a thing that is
  #   fine.
  # - `degraded` / `down` are observed failures, `down` being total.
  #
  # The composite probe's older ladder (ok/not_measured/degraded/down) is a
  # subsequence of this one in the same relative order, so no contributor
  # changes meaning by moving here.
  class ComponentStatus < ApplicationRecord
    # ── Verdicts ────────────────────────────────────────────────────────────
    OK            = "ok"
    HELD          = "held"
    PROGRESSING   = "progressing"
    NOT_MEASURED  = "not_measured"
    DEGRADED      = "degraded"
    DOWN          = "down"

    # Ascending severity. The integer is an ordering device only; never
    # persist it, and never assume the gaps mean anything.
    RANK = {
      OK => 0,
      HELD => 1,
      PROGRESSING => 2,
      NOT_MEASURED => 3,
      DEGRADED => 4,
      DOWN => 5
    }.freeze

    VERDICTS = RANK.keys.freeze

    # Verdicts that mean "a person should look at this". `not_measured` is in
    # here on purpose: blindness is actionable.
    UNHEALTHY_VERDICTS = [ NOT_MEASURED, DEGRADED, DOWN ].freeze

    # ── Remediation states (design §4.3) ────────────────────────────────────
    # Derived from SignalState / RemediationOutcome / ApprovalRequest and the
    # lane binding by A5 — NEVER hand-written by a contributor.
    REMEDIATION_NONE            = "none"
    REMEDIATION_AUTO_IN_PROGRESS = "auto_in_progress"
    REMEDIATION_AWAITING_OPERATOR = "awaiting_operator"
    REMEDIATION_STUCK           = "stuck"
    REMEDIATION_REMEDIATED      = "remediated"
    REMEDIATION_NOT_ACTUATABLE  = "not_actuatable"

    REMEDIATION_STATES = [
      REMEDIATION_NONE,
      REMEDIATION_AUTO_IN_PROGRESS,
      REMEDIATION_AWAITING_OPERATOR,
      REMEDIATION_STUCK,
      REMEDIATION_REMEDIATED,
      REMEDIATION_NOT_ACTUATABLE
    ].freeze

    # The ref used when a contributor's ENUMERATION itself raised, so there is
    # no per-record ref to key on but the failure must still be visible.
    WILDCARD_REF = "*"

    # ── Associations ────────────────────────────────────────────────────────
    # Optional on purpose: a process-wide kind (`account_scoped? == false`)
    # has no tenant, and most kinds carry no environment.
    belongs_to :account, optional: true
    belongs_to :environment, class_name: "Ai::Environment", optional: true

    # ── JSON defaults live HERE, as lambdas (convention), so the database
    # holds no second copy of the same decision.
    attribute :presentation,  :json, default: -> { {} }
    attribute :links,         :json, default: -> { [] }
    attribute :actions,       :json, default: -> { [] }
    attribute :conditions,    :json, default: -> { [] }
    attribute :dependencies,  :json, default: -> { [] }
    attribute :remediation,   :json, default: -> { {} }

    # ── Validations ─────────────────────────────────────────────────────────
    validates :component_kind, presence: true, length: { maximum: 255 }
    validates :component_ref, presence: true, length: { maximum: 255 },
                              uniqueness: { scope: %i[account_id component_kind] }
    validates :verdict, inclusion: { in: VERDICTS }
    validates :display_name, length: { maximum: 255 }, allow_nil: true
    validates :observed_generation, length: { maximum: 255 }, allow_nil: true
    validate  :conditions_is_an_array
    validate  :dependencies_is_an_array
    validate  :remediation_state_is_known

    # ── Scopes ──────────────────────────────────────────────────────────────
    scope :for_kind,    ->(kind) { where(component_kind: kind) }
    scope :for_account, ->(account) { where(account_id: account.is_a?(::Account) ? account.id : account) }
    # Rows a non-account-scoped contributor wrote. They render in a "shared
    # infrastructure" section and never enter a per-account rollup.
    scope :shared,      -> { where(account_id: nil) }
    scope :with_verdict, ->(verdict) { where(verdict: verdict) }
    scope :unhealthy,   -> { where(verdict: UNHEALTHY_VERDICTS) }
    scope :held,        -> { where(verdict: HELD) }
    # The reap arm's read: everything not seen since `cutoff`. A row that was
    # never swept (null) counts as stale — it cannot have a live contributor.
    scope :not_seen_since, ->(cutoff) { where("last_seen_sweep_at IS NULL OR last_seen_sweep_at < ?", cutoff) }

    # The environment filter is THREE-VALUED (design §4.6), so the third case
    # gets a scope of its own rather than being someone's `where.not`, which
    # would silently drop the plane-less rows.
    scope :in_plane,      ->(environment_id) { where(environment_id: environment_id) }
    scope :plane_less,    -> { where(environment_id: nil) }
    scope :out_of_plane,  ->(environment_id) { where.not(environment_id: nil).where.not(environment_id: environment_id) }

    class << self
      def rank_of(verdict)
        RANK.fetch(verdict.to_s, RANK[NOT_MEASURED])
      end

      # The worst of a set of verdicts. An EMPTY set is `not_measured`, never
      # `ok`: nothing observed is not the same as nothing wrong.
      def worst(verdicts)
        list = Array(verdicts).compact.map(&:to_s)
        return NOT_MEASURED if list.empty?

        list.max_by { |v| rank_of(v) }
      end

      # The worst verdict EXCLUDING operator intent — the "operational"
      # verdict of design §4.1. All-held reads `ok`, because a fully drained
      # scope has nothing failing in it.
      def worst_operational(verdicts)
        list = Array(verdicts).compact.map(&:to_s).reject { |v| v == HELD }
        return OK if list.empty? && Array(verdicts).any?

        worst(list)
      end
    end

    def rank
      self.class.rank_of(verdict)
    end

    def unhealthy?
      UNHEALTHY_VERDICTS.include?(verdict)
    end

    def held?
      verdict == HELD
    end

    # The identity a dependency edge points at.
    def component_key
      [ component_kind, component_ref ]
    end

    # When this component last CHANGED, taken as the most recent condition
    # transition. Nil when nothing has ever transitioned.
    def last_transition_at
      Array(conditions).filter_map { |c| c.is_a?(Hash) ? c["last_transition_at"] || c[:last_transition_at] : nil }
                       .filter_map { |t| t.is_a?(String) ? (Time.zone.parse(t) rescue nil) : t }
                       .max
    end

    private

    def conditions_is_an_array
      errors.add(:conditions, "must be an array") unless conditions.is_a?(Array)
    end

    def dependencies_is_an_array
      errors.add(:dependencies, "must be an array") unless dependencies.is_a?(Array)
    end

    def remediation_state_is_known
      return unless remediation.is_a?(Hash)

      state = remediation["state"] || remediation[:state]
      return if state.blank? || REMEDIATION_STATES.include?(state.to_s)

      errors.add(:remediation, "state #{state} is not one of #{REMEDIATION_STATES.join(', ')}")
    end
  end
end
