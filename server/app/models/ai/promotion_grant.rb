# frozen_string_literal: true

module Ai
  # A TIME-BOXED PROMOTION GRANT: a person's standing, narrow permission for
  # ONE agent to perform ONE gated category into ONE environment, optionally
  # only for some modules, at most `max_uses` times, until `expires_at`.
  #
  # Why it exists. A promotion into a protected plane parks for a person (the
  # plane's release.promote row, or an environment escalation), the parked
  # request is decidable only from a person's own session
  # (Ai::Approvals::HumanSessionPolicy, protected plane), and the agent that
  # asked may never decide it (Ai::ApprovalRequest#requester_excluded?). An
  # operator who wants an agent to ship a release train for the next few hours
  # had no lever short of relaxing the policy for EVERY caller. A grant is that
  # lever, bounded on every axis and revocable at any time.
  #
  # Where it acts. Ai::AutonomyGate, in its require_approval arm only: a
  # matching grant is consumed (Ai::PromotionGrants::Ledger.consume!) and the
  # operation proceeds instead of parking. It never lifts a block, the kill
  # switch, a human-only call or any other reason a request needs a person's
  # session — see the gate.
  #
  # Who may issue one. Only a person, from their own session
  # (Ai::ApprovalDecision::REST_SESSION). The row refuses a create naming any
  # other origin, so no tool door can mint one whatever credential it carries;
  # and nothing about a grant can change after issue except its use count and a
  # one-way revocation, so no door can extend or un-revoke one either.
  class PromotionGrant < ApplicationRecord
    self.table_name = "ai_promotion_grants"

    # The categories a grant may name. Each needs an extension catalog
    # (Ai::PromotionGrants::Catalog) to say which permission a granter must
    # hold; with none, nothing can be issued.
    CATEGORIES = %w[release.promote].freeze
    MAX_LIFETIME = 24.hours
    REASON_MAX_LENGTH = 2000
    UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    # Everything a grant says. Fixed at issue: a grant is re-issued, never edited.
    TERMS = %w[account_id granted_by_id ai_agent_id environment_id action_category module_ids
               max_uses expires_at reason].freeze
    ISSUE_REFUSAL = "A promotion grant is issued only by a person in their own session, never through a tool, " \
                    "an impersonation, an account-switch or a service session"

    # The door a create came through (Ai::ApprovalDecision ORIGINS). Not a
    # column: set by the issuer for the one write it makes, and checked here.
    attr_accessor :issuing_origin

    belongs_to :account
    belongs_to :granted_by, class_name: "User"
    belongs_to :revoked_by, class_name: "User", optional: true
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", inverse_of: false
    belongs_to :environment, class_name: "Ai::Environment"
    has_many :deferred_operations, class_name: "Ai::DeferredOperation", foreign_key: "promotion_grant_id",
                                   inverse_of: :promotion_grant, dependent: :nullify

    attribute :module_ids, default: -> { [] }

    before_validation :normalize_module_ids, if: -> { new_record? || will_save_change_to_module_ids? }

    validates :action_category, presence: true, inclusion: { in: CATEGORIES }
    validates :reason, presence: true, length: { maximum: REASON_MAX_LENGTH }
    validates :expires_at, presence: true
    validates :uses_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :max_uses, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate :issued_from_own_session, on: :create
    validate :lifetime_within_cap, on: :create
    validate :references_in_account
    validate :module_ids_are_uuids
    validate :uses_within_max
    validate :terms_unchanged, on: :update
    validate :revocation_is_final, on: :update

    scope :recent, -> { order(created_at: :desc) }
    scope :unrevoked, -> { where(revoked_at: nil) }
    scope :unexpired, ->(now = Time.current) { where(arel_table[:expires_at].gt(now)) }
    scope :with_uses_left, -> { where("max_uses IS NULL OR uses_count < max_uses") }
    scope :active, ->(now = Time.current) { unrevoked.unexpired(now).with_uses_left }

    def revoked?
      revoked_at.present?
    end

    def expired?(now = Time.current)
      expires_at.present? && expires_at <= now
    end

    def exhausted?
      max_uses.present? && uses_count.to_i >= max_uses
    end

    def active?(now = Time.current)
      !revoked? && !expired?(now) && !exhausted?
    end

    # revoked > expired > exhausted > active: the first reason it stopped.
    def status(now = Time.current)
      return "revoked" if revoked?
      return "expired" if expired?(now)
      return "exhausted" if exhausted?

      "active"
    end

    def uses_remaining
      max_uses.nil? ? nil : [ max_uses - uses_count.to_i, 0 ].max
    end

    def seconds_remaining(now = Time.current)
      return 0 unless active?(now)

      (expires_at - now).to_i
    end

    # Empty module_ids means any module.
    def covers_module?(module_id)
      module_ids.blank? || module_ids.include?(module_id.to_s)
    end

    class AlreadyRevoked < StandardError; end

    # One-way. Raises AlreadyRevoked when already revoked.
    def revoke!(by:)
      raise AlreadyRevoked, "promotion grant #{id} is already revoked" if revoked?

      update!(revoked_at: Time.current, revoked_by: by)
    end

    private

    # Read from the RAW value: the uuid array type casts a malformed id to nil,
    # which would otherwise drop it silently and widen the grant.
    def normalize_module_ids
      assigned = read_attribute_before_type_cast("module_ids")
      raw = Array(assigned.is_a?(Array) ? assigned : module_ids).map { |id| id.to_s.strip.downcase }.reject(&:empty?).uniq
      @malformed_module_ids = raw.reject { |id| id.match?(UUID_FORMAT) }
      self.module_ids = raw - @malformed_module_ids
    end

    def issued_from_own_session
      return if ::Ai::ApprovalDecision.human_session_origin?(issuing_origin)

      errors.add(:base, ISSUE_REFUSAL)
    end

    def lifetime_within_cap
      return if expires_at.blank?

      now = Time.current
      errors.add(:expires_at, "must be in the future") if expires_at <= now
      errors.add(:expires_at, "may be at most 24 hours after the grant is issued") if expires_at > now + MAX_LIFETIME
    end

    def references_in_account
      return if account_id.blank?

      errors.add(:agent, "must be an agent in this account") if agent && agent.account_id != account_id
      errors.add(:environment, "must be an environment in this account") if environment && environment.account_id != account_id
      errors.add(:granted_by, "must be a user in this account") if granted_by && granted_by.account_id != account_id
      errors.add(:revoked_by, "must be a user in this account") if revoked_by && revoked_by.account_id != account_id
    end

    def module_ids_are_uuids
      bad = Array(@malformed_module_ids)
      errors.add(:module_ids, "must be module ids (uuids): #{bad.join(', ')}") if bad.any?
    end

    def uses_within_max
      return if max_uses.nil? || uses_count.nil?

      errors.add(:uses_count, "cannot exceed max_uses") if uses_count > max_uses
    end

    def terms_unchanged
      changed_terms = TERMS.select { |term| will_save_change_to_attribute?(term) }
      return if changed_terms.empty?

      errors.add(:base, "A grant's terms are fixed at issue (#{changed_terms.join(', ')}); revoke it and issue a new one")
    end

    def revocation_is_final
      return unless attribute_in_database(:revoked_at).present?
      return unless will_save_change_to_revoked_at? || will_save_change_to_revoked_by_id?

      errors.add(:revoked_at, "is final: a revoked grant cannot be restored")
    end
  end
end
