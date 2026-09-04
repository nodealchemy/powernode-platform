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

    def allows_delegate_type?(agent_type)
      allowed_delegate_types.blank? || allowed_delegate_types.include?(agent_type.to_s)
    end
  end
end
