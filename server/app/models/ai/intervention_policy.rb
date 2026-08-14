# frozen_string_literal: true

module Ai
  class InterventionPolicy < ApplicationRecord
    self.table_name = "ai_intervention_policies"

    SCOPES = %w[global agent action_type].freeze
    POLICIES = %w[auto_approve notify_and_proceed require_approval silent block].freeze

    # Static categories owned by core. Extensions append at boot via
    # `Ai::InterventionPolicy.register_category!("ext.action_name")` from
    # their Engine#after_initialize. The registry is thread-safe at boot
    # (single-threaded init); reads are lock-free at request time.
    STATIC_CATEGORIES = %w[
      approval proposal escalation status_update issue_alert
      feedback
      project.adapt project.cost_control project.scale_horizontal project.relocate project.schema_change project.security_change
      dev.pull_task dev.complete_task dev.commit_to_branch
      dev.multi_file_change dev.merge
      *
    ].freeze

    @category_registry = Set.new(STATIC_CATEGORIES)
    @category_registry_mutex = Mutex.new

    class << self
      # Register an action category at boot. Called from extension Engines'
      # `after_initialize` blocks. Idempotent — calling twice with the same
      # name is a no-op. Returns the category name.
      def register_category!(name)
        return name unless name.is_a?(String) && !name.strip.empty?

        @category_registry_mutex.synchronize { @category_registry << name }
        name
      end

      def register_categories!(names)
        names.each { |n| register_category!(n) }
      end

      def category_registered?(name)
        @category_registry.include?(name)
      end

      def registered_categories
        @category_registry.to_a.sort
      end
    end

    # Associations
    belongs_to :account
    belongs_to :user, optional: true
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true
    belongs_to :approval_chain, class_name: "Ai::ApprovalChain", optional: true

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

    # A nil-agent row matches ANY caller here — agent dispatches included.
    # Audience separation is enforced one level up (IMP-bfbf8052e179):
    # Ai::InterventionPolicyService#resolve considers ONLY rows scoped to the
    # calling agent when an agent is present, so nil-agent rows bind
    # exclusively on the agent-less (operator/global) path. Do not rely on
    # this method alone to keep an operator-intent row away from agents.
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
        agent_tier = trust_score&.tier || "supervised"
        min_tier = conditions["trust_tier_minimum"]
        return false if tier_order.index(agent_tier).to_i < tier_order.index(min_tier).to_i
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
