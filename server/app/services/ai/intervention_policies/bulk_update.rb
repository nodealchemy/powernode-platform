# frozen_string_literal: true

module Ai
  module InterventionPolicies
    # Upserts a batch of intervention-policy rows for the settings panel's save
    # (PATCH /api/v1/ai/intervention_policies/bulk). One entry per control the
    # operator touched: { action_category, policy, scope?, agent_id?, ... }.
    #
    # Per entry, and the batch keeps going past a refused one, so a 422 does not
    # mean nothing was written — callers read `changed` and `errors`.
    #
    # - The category must be REGISTERED (Ai::InterventionPolicy.category_registered?).
    #   An unregistered one is a durable control for an action nothing executes.
    # - An ABSENT key means "leave it alone", not "reset it" (IMP-bef43160636f).
    #   A control edits the verb only, so a verb save must not unassign the
    #   row's approval chain or reset a tuned priority. The defaults apply only
    #   to a row being created; a PRESENT nil approval_chain_id still unassigns.
    # - A write that could lift the person-session mark needs that person's own
    #   session (IMP-03134d9452d2); refused per entry, nothing written for it.
    # - agent_id and approval_chain_id are resolved through the account, never
    #   assigned raw: the associations carry no account check, so a raw id lets
    #   one account point its row at another's agent or chain (and gate its
    #   actions on the other account's approvers). An id that does not resolve,
    #   foreign or nonexistent, is refused per entry before anything is written.
    class BulkUpdate
      Result = Struct.new(:changed, :errors, keyword_init: true)

      def initialize(account:, own_human_session:)
        @account = account
        @own_human_session = own_human_session
      end

      def call(updates)
        changed = 0
        errors = []

        updates.each_with_index do |raw, idx|
          error = apply(normalize(raw))
          error ? errors << "[#{idx}] #{error}" : changed += 1
        end

        Result.new(changed: changed, errors: errors)
      end

      private

      attr_reader :account

      def normalize(raw)
        attrs = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
        attrs.with_indifferent_access
      end

      # Returns an error string, or nil when the row saved.
      def apply(attrs)
        category = attrs[:action_category]
        return "action_category required" if category.blank?
        return "unknown category #{category}" unless ::Ai::InterventionPolicy.category_registered?(category)

        verb = attrs[:policy]
        return "policy required" if verb.blank?
        return "invalid policy #{verb}" unless ::Ai::InterventionPolicy::POLICIES.include?(verb)

        reference_error = unresolvable_reference(attrs)
        return reference_error if reference_error

        scope = attrs[:scope].presence || (attrs[:agent_id].present? ? "agent" : "global")
        policy = ::Ai::InterventionPolicy.find_or_initialize_by(
          account: account, action_category: category, scope: scope, ai_agent_id: attrs[:agent_id], user_id: nil
        )
        assign(policy, attrs, verb, scope)

        before = policy.new_record? ? nil : policy.attribute_in_database(:conditions)
        if !@own_human_session &&
           ::Ai::Approvals::HumanSessionPolicy.mark_lifting_write?(before: before, after: policy.conditions)
          return ::Ai::Approvals::HumanSessionPolicy::MARK_WRITE_REFUSAL
        end

        policy.save ? nil : policy.errors.full_messages.join(", ")
      end

      # The account's own agent or a global canonical one, and the account's own
      # chain; anything else answers with an error string.
      def unresolvable_reference(attrs)
        agent_id = attrs[:agent_id].presence
        if agent_id && !::Ai::Agent.for_account(account.id).exists?(id: agent_id)
          return "unknown agent #{agent_id}"
        end

        chain_id = attrs[:approval_chain_id].presence
        if chain_id && !::Ai::ApprovalChain.where(account: account).exists?(id: chain_id)
          return "unknown approval chain #{chain_id}"
        end

        nil
      end

      # Each fallback tests new_record? rather than the attribute's current
      # value: the columns carry DB defaults, so an unsaved row already answers
      # non-nil and `attrs[:priority] || policy.priority` would create every new
      # row at priority 0.
      def assign(policy, attrs, verb, scope)
        created = policy.new_record?
        policy.policy = verb
        policy.priority = attrs[:priority] || (created ? (scope == "agent" ? 10 : 5) : policy.priority)
        policy.is_active =
          if attrs[:is_active].nil?
            created ? true : policy.is_active
          else
            ActiveModel::Type::Boolean.new.cast(attrs[:is_active])
          end
        policy.preferred_channels =
          Array(attrs[:preferred_channels]).presence ||
          (created ? %w[notification] : policy.preferred_channels.presence || %w[notification])
        policy.conditions = attrs[:conditions].presence || policy.conditions || {}
        policy.approval_chain_id = attrs.key?(:approval_chain_id) ? attrs[:approval_chain_id] : policy.approval_chain_id
      end
    end
  end
end
