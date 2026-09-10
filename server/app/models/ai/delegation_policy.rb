# frozen_string_literal: true

module Ai
  class DelegationPolicy < ApplicationRecord
    self.table_name = "ai_delegation_policies"

    INHERITANCE_POLICIES = %w[conservative moderate permissive].freeze

    # A policy is either an ACCOUNT's customisation for an agent (account_id
    # set) or the CANONICAL default for a global seeded agent (account_id nil,
    # written by seeds). Resolution prefers the account's own row — see
    # .resolve_for — mirroring GloballyScopable's account-override-first rule.
    belongs_to :account, optional: true
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"

    # Scoped to the account, not global: two accounts may each hold a policy
    # for the same canonical agent, and a global row may sit beside them. The
    # schema enforces the same pair with two partial unique indexes
    # (account rows / global rows), so a nil scope here means "IS NULL".
    validates :agent_id, uniqueness: { scope: :account_id }
    validates :max_depth, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
    validates :budget_delegation_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :inheritance_policy, inclusion: { in: INHERITANCE_POLICIES }

    attribute :allowed_delegate_types, :json, default: -> { [] }
    attribute :delegatable_actions, :json, default: -> { [] }

    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :global, -> { where(account_id: nil) }
    # Visible to an account: the canonical global rows plus its own rows.
    scope :for_account, ->(account_id) { where(account_id: [ nil, account_id ]) }

    # The policy that governs `agent_id` inside `account_id`: the account's own
    # row when it has one, otherwise the canonical global row, otherwise nil.
    # Every reader of an agent's delegation authority goes through here so the
    # override rule has exactly one author.
    def self.resolve_for(agent_id:, account_id:)
      for_account(account_id)
        .where(agent_id: agent_id)
        .order(Arel.sql("account_id IS NULL"))
        .first
    end

    def global?
      account_id.nil?
    end

    def allows_action?(action_type)
      delegatable_actions.blank? || delegatable_actions.include?(action_type.to_s)
    end

    # HIER-P0: an EMPTY allowed_delegate_types means NONE, not ANY.
    #
    # This was `blank? || include?`, which read a deliberately empty allowlist
    # as unrestricted — so the nine canonical leaves seeded with
    # `allowed_delegate_types: []` (CORE_HIERARCHY_CHILD_DELEGATION in
    # db/seeds/ai_agent_hierarchy_seed.rb) could delegate to anything. The
    # seeds had already grown a "no such type" sentinel to express "nobody"
    # around that fail-open, and both seed files carry comments warning that an
    # empty list would hand out unrestricted delegation. The allowlist is now
    # read literally, so the sentinel and an empty list mean the same thing.
    #
    # Governance is opted into by the POLICY ROW, not by the list: with no row
    # at all Ai::Autonomy::DelegationAuthorityService#validate_delegation still
    # returns allowed: true, so this does not turn ungoverned agents into
    # leaves. Note the asymmetry with #allows_action? above, which keeps
    # blank-means-any — deliberately out of HIER-P0's scope.
    #
    # There is no wildcard token: "may delegate to any type" is now expressed
    # by enumerating the types (or by holding no policy row).
    def allows_delegate_type?(agent_type)
      Array(allowed_delegate_types).map(&:to_s).include?(agent_type.to_s)
    end
  end
end
