# frozen_string_literal: true

module Ai
  class InterventionPolicy < ApplicationRecord
    self.table_name = "ai_intervention_policies"

    SCOPES = %w[global agent action_type].freeze
    POLICIES = %w[auto_approve notify_and_proceed require_approval silent block].freeze

    ACTION_CATEGORIES = %w[
      approval proposal escalation status_update issue_alert
      feedback *
    ].freeze

    # Associations
    belongs_to :account
    belongs_to :user, optional: true
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

    # Validations
    validates :scope, presence: true, inclusion: { in: SCOPES }
    validates :action_category, presence: true
    validates :policy, presence: true, inclusion: { in: POLICIES }
    validates :priority, presence: true, numericality: { only_integer: true }

    # JSON columns
    attribute :conditions, :json, default: -> { {} }
    attribute :preferred_channels, :json, default: -> { [] }

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :for_category, ->(category) { where(action_category: [category, "*"]) }
    scope :by_specificity, -> { order(priority: :desc) }

    # Instance methods
    def matches?(action_category:, agent: nil, user: nil)
      return false unless is_active?
      return false unless action_category_matches?(action_category)
      return false unless agent_matches?(agent)
      return false unless user_matches?(user)
      return false unless conditions_met?(agent)
      true
    end

    def specificity_score
      score = 0
      score += 10 if user_id.present?
      score += 5 if ai_agent_id.present?
      score += 2 if action_category != "*"
      score += priority
      score
    end

    private

    def action_category_matches?(category)
      action_category == "*" || action_category == category
    end

    def agent_matches?(agent_record)
      return true if ai_agent_id.nil?
      agent_record && ai_agent_id == agent_record.id
    end

    def user_matches?(user_record)
      return true if user_id.nil?
      user_record && user_id == user_record.id
    end

    def conditions_met?(agent_record)
      return true if conditions.blank?

      # Check trust tier minimum
      if conditions["trust_tier_minimum"].present? && agent_record
        tier_order = %w[supervised monitored trusted autonomous]
        trust_score = Ai::AgentTrustScore.find_by(agent_id: agent_record.id)
        return false unless trust_score
        return false if tier_order.index(trust_score.tier).to_i < tier_order.index(conditions["trust_tier_minimum"]).to_i
      end

      # Check severity minimum
      # (evaluated at lookup time by InterventionPolicyService)

      # Check quiet hours
      if conditions["quiet_hours"].present?
        quiet = conditions["quiet_hours"]
        current_hour = Time.current.hour
        return false if quiet["start"].to_i <= current_hour && current_hour < quiet["end"].to_i
      end

      true
    end
  end
end
