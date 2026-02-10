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
    def action_allowed?(action)
      return false if denied_actions.include?(action)
      return true if allowed_actions.empty? || allowed_actions.include?(action) || allowed_actions.include?("*")

      false
    end

    def tool_allowed?(tool_name)
      return false if denied_tools.include?(tool_name)
      return true if allowed_tools.empty? || allowed_tools.include?(tool_name) || allowed_tools.include?("*")

      false
    end

    def resource_allowed?(resource)
      return false if denied_resources.include?(resource)
      return true if allowed_resources.empty? || allowed_resources.include?(resource) || allowed_resources.include?("*")

      false
    end

    def communication_allowed?(from_agent_id, to_agent_id)
      rules = communication_rules
      return true if rules.blank?

      blocked = rules["blocked_pairs"] || []
      return false if blocked.any? { |pair| pair.include?(from_agent_id) && pair.include?(to_agent_id) }

      allowed = rules["allowed_pairs"]
      return true if allowed.nil?

      allowed.any? { |pair| pair.include?(from_agent_id) && pair.include?(to_agent_id) }
    end
  end
end
