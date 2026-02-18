# frozen_string_literal: true

module Ai
  class DelegationPolicy < ApplicationRecord
    self.table_name = "ai_delegation_policies"

    INHERITANCE_POLICIES = %w[conservative moderate permissive].freeze

    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "agent_id"

    validates :agent_id, uniqueness: true
    validates :max_depth, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
    validates :budget_delegation_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :inheritance_policy, inclusion: { in: INHERITANCE_POLICIES }

    attribute :allowed_delegate_types, :json, default: -> { [] }
    attribute :delegatable_actions, :json, default: -> { [] }

    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }

    def allows_action?(action_type)
      delegatable_actions.blank? || delegatable_actions.include?(action_type.to_s)
    end

    def allows_delegate_type?(agent_type)
      allowed_delegate_types.blank? || allowed_delegate_types.include?(agent_type.to_s)
    end
  end
end
