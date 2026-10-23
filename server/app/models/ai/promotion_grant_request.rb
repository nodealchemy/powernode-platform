# frozen_string_literal: true

module Ai
  # An AGENT'S REQUEST for a time-boxed promotion grant (Ai::PromotionGrant),
  # with its terms frozen at request time. It parks as a human-only approval
  # card (Ai::PromotionGrants::Requests.request!); a person approves it in
  # their own session; the grant is then issued IN THAT PERSON'S NAME with
  # exactly these terms (#on_approval_decision). Nothing about it is a grant:
  # until a person's own-session approval, it authorizes nothing.
  #
  # Who may ask: an agent, for itself only (the agent is the calling tool's
  # own, never a param). What it may be bound to: the requesting MCP session
  # or Platform Developer run, resolved from the call's own state
  # (Ai::PromotionGrants::Binding), or nothing.
  #
  # Who may complete it: the approval request is marked requires_human_session
  # EXPLICITLY (its category matches no default human-session pattern, so
  # without the mark a chain's approve-on-timeout could approve it), and the
  # grant is issued only for Ai::ApprovalRequest#confirming_approver, a person
  # whose approving decision row records their own session. Any other approval
  # (a timeout, an override with no such decision) issues nothing and leaves
  # an issue_refused row.
  class PromotionGrantRequest < ApplicationRecord
    self.table_name = "ai_promotion_grant_requests"

    STATUSES = %w[pending issued refused rejected expired cancelled].freeze
    MAX_PENDING_PER_AGENT = 3
    # The terms a request freezes, in the shape the ledger issues them.
    TERMS = %w[ai_agent_id environment_id action_category module_ids max_uses lifetime_seconds reason
               granter_driven_only binding_kind binding_id].freeze
    MANAGE_PERMISSION = "ai.promotion_grants.manage"
    APPROVAL_CATEGORY = "promotion_grant_issue"

    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", inverse_of: false
    belongs_to :environment, class_name: "Ai::Environment"
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :decided_by, class_name: "User", optional: true
    belongs_to :promotion_grant, class_name: "Ai::PromotionGrant", optional: true
    belongs_to :approval_request, class_name: "Ai::ApprovalRequest", optional: true

    attribute :module_ids, default: -> { [] }

    before_validation :normalize_module_ids, if: -> { new_record? || will_save_change_to_module_ids? }

    validates :status, inclusion: { in: STATUSES }
    validates :action_category, presence: true
    validates :reason, presence: true, length: { maximum: ::Ai::PromotionGrant::REASON_MAX_LENGTH }
    validates :lifetime_seconds, numericality: { only_integer: true, greater_than: 0 }
    validates :max_uses, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate :category_grantable, on: :create
    validate :lifetime_within_cap, on: :create
    validate :strict_plane_bounds, on: :create
    validate :binding_pair
    validate :references_in_account
    validate :module_ids_are_uuids
    validate :terms_unchanged, on: :update

    scope :pending, -> { where(status: "pending") }
    scope :recent, -> { order(created_at: :desc) }

    def pending?
      status == "pending"
    end

    def terms
      TERMS.index_with { |term| self[term] }
    end

    def binding_description
      ::Ai::PromotionGrants::Binding.describe(kind: binding_kind, id: binding_id, agent: agent)
    end

    # The approval seam (Ai::ApprovalRequest#notify_source_of_decision).
    def on_approval_decision(request)
      return ::Ai::ApprovalRequest::DISPATCH_NOOP unless pending?
      return ::Ai::ApprovalRequest::DISPATCH_NOOP if approval_request_id.present? && request.id != approval_request_id

      case request.status
      when "approved" then issue_from!(request)
      when "rejected" then close!("rejected", "rejected by a person")
      when "expired"  then close!("expired", "the request expired undecided")
      when "cancelled" then close!("cancelled", "the request was cancelled")
      else return ::Ai::ApprovalRequest::DISPATCH_NOOP
      end

      ::Ai::ApprovalRequest::DISPATCH_EXECUTED
    end

    # L9: an approval that would complete this request is refused, by name,
    # from someone who could not issue the grant (Ai::ApprovalRequest#record_decision!).
    def approval_decider_refusal(approver)
      granter_refusal(approver)
    end

    private

    # The only issuing arm. Reads the person and the door off the decision row
    # itself, re-checks that person's granter permissions now, and issues
    # through the ledger, which refuses (and records) any non-session door.
    def issue_from!(request)
      decision = request.confirming_decision
      approver = decision&.approver
      if approver.nil?
        return refuse!("No person approved this request in their own session (an approval on timeout, or one " \
                       "recorded from any other door, issues nothing)", approver: nil, origin: decision&.origin)
      end

      refusal = granter_refusal(approver)
      return refuse!(refusal, approver: approver, origin: decision.origin) if refusal

      if bound? && !::Ai::PromotionGrants::Binding.target_live?(kind: binding_kind, id: binding_id,
                                                                  account_id: account_id, agent_id: ai_agent_id)
        return refuse!("The #{binding_kind.tr('_', ' ')} this request is bound to has ended, so nothing was issued",
                       approver: approver, origin: decision.origin)
      end

      grant = ::Ai::PromotionGrants::Ledger.issue!(
        account: account, granted_by: approver, origin: decision.origin, grant_request: self,
        attributes: {
          ai_agent_id: ai_agent_id, environment_id: environment_id, action_category: action_category,
          module_ids: module_ids, max_uses: max_uses, reason: reason, granter_driven_only: granter_driven_only,
          binding_kind: binding_kind, binding_id: binding_id,
          # Counted from the approval, never from the request.
          expires_at: Time.current + lifetime_seconds.seconds
        }
      )
      update!(status: "issued", promotion_grant: grant, decided_by: approver, decided_at: Time.current)
    rescue ::Ai::PromotionGrants::Ledger::Refused => e
      # The ledger has already written the issue_refused row.
      update!(status: "refused", refusal_reason: e.message, decided_by: approver, decided_at: Time.current)
    end

    def bound?
      binding_kind.present?
    end

    # Nothing is issued; the refusal is recorded on this request and audited.
    def refuse!(message, approver:, origin:)
      ::Ai::PromotionGrants::Ledger.audit_refused!(
        account: account, granted_by: approver, origin: origin, message: message, grant_request: self,
        attributes: terms.merge("account_id" => account_id)
      )
      update!(status: "refused", refusal_reason: message, decided_by: approver, decided_at: Time.current)
    end

    def close!(new_status, why)
      update!(status: new_status, refusal_reason: why, decided_at: Time.current)
      ::AuditLog.create!(
        account_id: account_id, user: nil, action: ::Ai::PromotionGrants::Ledger::REQUEST_CLOSED, source: "system",
        resource_type: self.class.name, resource_id: id, severity: "low", risk_level: "low",
        new_values: { "status" => new_status, "reason" => why }, metadata: terms.merge("status" => new_status)
      )
    end

    # What the granter of THIS grant must hold, asked of the approver at
    # approval time: the grants manage permission, and the gated verb's own.
    def granter_refusal(approver)
      return "Only a person may approve a promotion grant request" if approver.nil?
      return "Approving a promotion grant needs #{MANAGE_PERMISSION}" unless approver.has_permission?(MANAGE_PERMISSION)

      verb_permission = ::Ai::PromotionGrants::Catalog.required_permission(action_category)
      return "No installed extension declares #{action_category} as grantable" if verb_permission.nil?
      return nil if approver.has_permission?(verb_permission)

      "Granting #{action_category} needs the permission the action itself requires (#{verb_permission})"
    end

    def normalize_module_ids
      assigned = read_attribute_before_type_cast("module_ids")
      raw = Array(assigned.is_a?(Array) ? assigned : module_ids).map { |id| id.to_s.strip.downcase }.reject(&:empty?).uniq
      @malformed_module_ids = raw.reject { |id| id.match?(::Ai::PromotionGrant::UUID_FORMAT) }
      self.module_ids = raw - @malformed_module_ids
    end

    def category_grantable
      return if action_category.blank? || ::Ai::PromotionGrants::Grantable.grantable?(action_category)

      errors.add(:action_category, "#{action_category} is not a category a promotion grant may name")
    end

    def lifetime_within_cap
      return if lifetime_seconds.blank? || environment.nil?

      cap = ::Ai::PromotionGrant.max_lifetime_for(environment)
      return if lifetime_seconds <= cap.to_i

      errors.add(:lifetime_seconds, "may be at most #{(cap / 1.hour).to_i} hours for #{environment.slug}")
    end

    # The same bounds a person's grant meets on a strict plane, at request
    # time, so the card shows terms that can actually be issued.
    def strict_plane_bounds
      return unless ::Ai::PromotionGrant.strict_environment?(environment)

      plane = environment.slug
      limit = ::Ai::PromotionGrant::STRICT_MAX_USES
      if max_uses.nil? || max_uses > limit
        errors.add(:max_uses, "is required for #{plane}, a strict plane: max uses (1-#{limit})")
      end
      errors.add(:module_ids, "must name at least one module for #{plane}, a strict plane") if module_ids.blank?
    end

    def binding_pair
      return if binding_kind.blank? && binding_id.blank?

      if !::Ai::PromotionGrant::BINDING_KINDS.include?(binding_kind.to_s)
        errors.add(:binding_kind, "must be one of #{::Ai::PromotionGrant::BINDING_KINDS.join(', ')}")
      elsif binding_id.blank?
        errors.add(:binding_id, "is required with a binding kind")
      end
    end

    def references_in_account
      return if account_id.blank?

      errors.add(:agent, "must be an agent in this account") if agent && agent.account_id != account_id
      errors.add(:environment, "must be an environment in this account") if environment && environment.account_id != account_id
    end

    def module_ids_are_uuids
      bad = Array(@malformed_module_ids)
      errors.add(:module_ids, "must be module ids (uuids): #{bad.join(', ')}") if bad.any?
    end

    def terms_unchanged
      changed = TERMS.select { |term| will_save_change_to_attribute?(term) }
      errors.add(:base, "A request's terms are frozen (#{changed.join(', ')})") if changed.any?
    end
  end
end
