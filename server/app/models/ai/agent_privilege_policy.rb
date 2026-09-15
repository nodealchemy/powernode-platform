# frozen_string_literal: true

module Ai
  class AgentPrivilegePolicy < ApplicationRecord
    self.table_name = "ai_agent_privilege_policies"

    # ==========================================
    # Constants
    # ==========================================
    POLICY_TYPES = %w[system trust_tier custom].freeze
    TRUST_TIERS = %w[supervised monitored trusted autonomous].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account

    # ==========================================
    # Validations
    # ==========================================
    validates :policy_name, presence: true, uniqueness: { scope: :account_id }
    validates :policy_type, presence: true, inclusion: { in: POLICY_TYPES }
    validates :trust_tier, inclusion: { in: TRUST_TIERS }, allow_nil: true
    validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where(active: true) }
    scope :inactive, -> { where(active: false) }
    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :by_trust_tier, ->(tier) { where(trust_tier: tier) }
    scope :by_type, ->(type) { where(policy_type: type) }
    scope :system_policies, -> { where(policy_type: "system") }
    scope :by_priority, -> { order(priority: :desc) }
    scope :applicable_to, ->(agent_id, trust_tier) {
      active.where(
        "agent_id = :agent_id OR trust_tier = :trust_tier OR (agent_id IS NULL AND trust_tier IS NULL AND policy_type = 'system')",
        agent_id: agent_id,
        trust_tier: trust_tier
      ).order(priority: :desc)
    }

    # ==========================================
    # Methods
    # ==========================================
    # A blank (empty or null) allow-list DENIES (operator rule 2026-09-08,
    # IMP-636a10c80024): unrestricted is spelled ["*"], so a writer that
    # forgets the list fails closed. The deny-list still bounds a wildcard.
    def action_allowed?(action)
      listed_and_not_denied?(allowed_actions, denied_actions, action)
    end

    def tool_allowed?(tool_name)
      listed_and_not_denied?(allowed_tools, denied_tools, tool_name)
    end

    def resource_allowed?(resource)
      listed_and_not_denied?(allowed_resources, denied_resources, resource)
    end

    def communication_allowed?(from_agent_id, to_agent_id)
      rules = communication_rules
      return true if rules.blank?

      blocked = rules["blocked_pairs"] || []
      return false if blocked.any? { |pair| pair_matches?(pair, from_agent_id, to_agent_id) }

      allowed = rules["allowed_pairs"]
      return true if allowed.nil?

      allowed.any? { |pair| pair_matches?(pair, from_agent_id, to_agent_id) }
    end

    private

    # A NULL deny-list denies too: the old reading raised on it and enforcement
    # failed closed, and Array(nil) would quietly read it as "nothing denied".
    def listed_and_not_denied?(allowed, denied, name)
      return false if denied.nil?

      denied = Array(denied)
      return false if denied.include?("*") || denied.include?(name)

      allowed = Array(allowed)
      allowed.include?("*") || allowed.include?(name)
    end

    # Match a communication pair, treating "*" as a wildcard that matches any agent ID.
    def pair_matches?(pair, from_agent_id, to_agent_id)
      return false unless pair.is_a?(Array) && pair.size == 2

      (pair[0] == "*" || pair[0] == from_agent_id) &&
        (pair[1] == "*" || pair[1] == to_agent_id) ||
        (pair[0] == "*" || pair[0] == to_agent_id) &&
        (pair[1] == "*" || pair[1] == from_agent_id)
    end
  end
end
