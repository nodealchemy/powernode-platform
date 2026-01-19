# frozen_string_literal: true

module Ai
  class CostOptimizationLog < ApplicationRecord
    include Auditable

    # ==========================================================================
    # CONSTANTS
    # ==========================================================================

    OPTIMIZATION_TYPES = %w[provider_switch model_downgrade caching batching rate_optimization usage_reduction].freeze
    STATUSES = %w[identified analyzing recommended applied validated rejected expired].freeze
    RESOURCE_TYPES = %w[provider workflow agent team account].freeze

    # ==========================================================================
    # ASSOCIATIONS
    # ==========================================================================

    belongs_to :account

    # ==========================================================================
    # VALIDATIONS
    # ==========================================================================

    validates :optimization_type, presence: true, inclusion: { in: OPTIMIZATION_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validate :validate_recommendation_structure

    # ==========================================================================
    # SCOPES
    # ==========================================================================

    scope :active, -> { where(status: %w[identified analyzing recommended]) }
    scope :applied, -> { where(status: "applied") }
    scope :validated, -> { where(status: "validated") }
    scope :pending, -> { where(status: %w[identified recommended]) }
    scope :by_type, ->(type) { where(optimization_type: type) }
    scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
    scope :high_impact, -> { where("potential_savings_usd >= ?", 10.0) }
    scope :recent, ->(period = 30.days) { where("created_at >= ?", period.ago) }
    scope :for_account, ->(account) { where(account: account) }

    # ==========================================================================
    # CALLBACKS
    # ==========================================================================

    before_validation :set_defaults
    before_create :set_identified_at

    # ==========================================================================
    # INSTANCE METHODS
    # ==========================================================================

    # Transition to analyzing status
    def start_analysis!
      update!(status: "analyzing")
    end

    # Mark as recommended with details
    def recommend!(recommendation_details)
      update!(
        status: "recommended",
        recommendation: recommendation.merge(recommendation_details)
      )
    end

    # Apply the optimization
    def apply!(applied_state = {})
      update!(
        status: "applied",
        applied_at: Time.current,
        after_state: applied_state
      )
    end

    # Validate the results
    def validate_results!(actual_savings:)
      update!(
        status: "validated",
        validated_at: Time.current,
        actual_savings_usd: actual_savings
      )
    end

    # Reject the optimization
    def reject!(reason = nil)
      attrs = { status: "rejected" }
      attrs[:recommendation] = recommendation.merge("rejection_reason" => reason) if reason
      update!(attrs)
    end

    # Calculate potential savings percentage
    def calculate_savings_percentage
      return 0.0 unless current_cost_usd.present? && current_cost_usd > 0 && potential_savings_usd.present?

      ((potential_savings_usd / current_cost_usd) * 100).round(2)
    end

    # Get the associated resource
    def resource
      return nil unless resource_type.present? && resource_id.present?

      case resource_type
      when "provider"
        Ai::Provider.find_by(id: resource_id)
      when "workflow"
        Ai::Workflow.find_by(id: resource_id)
      when "agent"
        Ai::Agent.find_by(id: resource_id)
      else
        nil
      end
    end

    # Get optimization summary
    def summary
      {
        id: id,
        type: optimization_type,
        status: status,
        description: description,
        resource: {
          type: resource_type,
          id: resource_id,
          name: resource&.try(:name)
        },
        financials: {
          current_cost: current_cost_usd,
          optimized_cost: optimized_cost_usd,
          potential_savings: potential_savings_usd,
          actual_savings: actual_savings_usd,
          savings_percentage: calculate_savings_percentage
        },
        recommendation: recommendation,
        timestamps: {
          identified_at: identified_at,
          applied_at: applied_at,
          validated_at: validated_at
        }
      }
    end

    # Check if high priority (significant savings)
    def high_priority?
      potential_savings_usd.present? && potential_savings_usd >= 50.0
    end

    # Check if expired (identified but not acted on for 30 days)
    def expired?
      return false unless status.in?(%w[identified recommended])

      identified_at.present? && identified_at < 30.days.ago
    end

    # Mark expired if applicable
    def mark_expired_if_applicable!
      update!(status: "expired") if expired?
    end

    # Class method: Identify optimization opportunities for an account
    def self.identify_opportunities_for(account)
      opportunities = []

      # Provider cost comparison
      provider_opportunities = identify_provider_opportunities(account)
      opportunities.concat(provider_opportunities)

      # Usage pattern analysis
      usage_opportunities = identify_usage_opportunities(account)
      opportunities.concat(usage_opportunities)

      # Caching opportunities
      caching_opportunities = identify_caching_opportunities(account)
      opportunities.concat(caching_opportunities)

      opportunities
    end

    # Class method: Get summary stats for account
    def self.stats_for_account(account, period: 30.days)
      logs = for_account(account).recent(period)

      {
        total_opportunities: logs.count,
        pending: logs.pending.count,
        applied: logs.applied.count,
        validated: logs.validated.count,
        total_potential_savings: logs.sum(:potential_savings_usd),
        total_actual_savings: logs.validated.sum(:actual_savings_usd),
        by_type: logs.group(:optimization_type).count,
        by_status: logs.group(:status).count,
        high_impact_count: logs.high_impact.count
      }
    end

    private

    def set_defaults
      self.recommendation ||= {}
      self.before_state ||= {}
      self.after_state ||= {}
      self.status ||= "identified"
    end

    def set_identified_at
      self.identified_at ||= Time.current
    end

    def validate_recommendation_structure
      return if recommendation.blank?

      unless recommendation.is_a?(Hash)
        errors.add(:recommendation, "must be a hash")
      end
    end

    # Identify provider switching opportunities
    def self.identify_provider_opportunities(account)
      opportunities = []

      # Get recent execution costs by provider
      provider_costs = Ai::AgentExecution
                         .joins(:agent)
                         .where(ai_agents: { account_id: account.id })
                         .where("ai_agent_executions.created_at >= ?", 30.days.ago)
                         .group(:ai_provider_id)
                         .sum(:cost_usd)

      # Find expensive providers with cheaper alternatives
      provider_costs.each do |provider_id, cost|
        provider = Ai::Provider.find_by(id: provider_id)
        next unless provider && cost > 10.0 # Minimum threshold

        # Check for cheaper alternatives with same capabilities
        cheaper_alternatives = account.ai_providers
                                       .where.not(id: provider_id)
                                       .where(is_active: true)
                                       .select { |p| (provider.capabilities - p.capabilities).empty? }

        next if cheaper_alternatives.empty?

        opportunities << {
          optimization_type: "provider_switch",
          resource_type: "provider",
          resource_id: provider_id,
          description: "Consider switching from #{provider.name} to a more cost-effective provider",
          current_cost_usd: cost,
          potential_savings_usd: cost * 0.2, # Conservative 20% estimate
          recommendation: {
            current_provider: provider.name,
            alternatives: cheaper_alternatives.map(&:name).first(3),
            reason: "Same capabilities at potentially lower cost"
          }
        }
      end

      opportunities
    end

    def self.identify_usage_opportunities(account)
      opportunities = []

      # Find workflows with high execution counts that could benefit from batching
      high_volume_workflows = Ai::WorkflowRun
                                .joins(:workflow)
                                .where(ai_workflows: { account_id: account.id })
                                .where("ai_workflow_runs.created_at >= ?", 7.days.ago)
                                .group(:ai_workflow_id)
                                .having("COUNT(*) > ?", 100)
                                .count

      high_volume_workflows.each do |workflow_id, count|
        workflow = Ai::Workflow.find_by(id: workflow_id)
        next unless workflow

        total_cost = Ai::WorkflowRun.where(ai_workflow_id: workflow_id)
                                    .where("created_at >= ?", 7.days.ago)
                                    .sum(:total_cost)

        opportunities << {
          optimization_type: "batching",
          resource_type: "workflow",
          resource_id: workflow_id,
          description: "High-volume workflow '#{workflow.name}' could benefit from batch processing",
          current_cost_usd: total_cost,
          potential_savings_usd: total_cost * 0.15, # 15% batch savings estimate
          recommendation: {
            workflow_name: workflow.name,
            executions_7d: count,
            suggestion: "Implement batch processing for similar requests"
          }
        }
      end

      opportunities
    end

    def self.identify_caching_opportunities(account)
      opportunities = []

      # Find agents with repetitive similar prompts
      # This would require more sophisticated analysis in production
      # Simplified version here

      high_usage_agents = Ai::AgentExecution
                            .joins(:agent)
                            .where(ai_agents: { account_id: account.id })
                            .where("ai_agent_executions.created_at >= ?", 7.days.ago)
                            .group(:ai_agent_id)
                            .having("COUNT(*) > ?", 50)
                            .sum(:cost_usd)

      high_usage_agents.each do |agent_id, cost|
        agent = Ai::Agent.find_by(id: agent_id)
        next unless agent && cost > 5.0

        opportunities << {
          optimization_type: "caching",
          resource_type: "agent",
          resource_id: agent_id,
          description: "Agent '#{agent.name}' has high usage - consider response caching",
          current_cost_usd: cost,
          potential_savings_usd: cost * 0.25, # 25% caching savings estimate
          recommendation: {
            agent_name: agent.name,
            suggestion: "Implement semantic caching for similar prompts"
          }
        }
      end

      opportunities
    end
  end
end
