# frozen_string_literal: true

module Ai
  class InterventionPolicyService
    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Resolve the effective policy for a given action category and context.
    # Uses most-specific-wins: user+agent > user > agent > global.
    #
    # @param action_category [String] e.g. "approval", "proposal", "escalation"
    # @param agent [Ai::Agent, nil]
    # @param user [User, nil]
    # @param severity [String, nil] "info", "warning", "critical"
    # @return [Hash] { policy: String, channels: Array, conditions: Hash }
    def resolve(action_category:, agent: nil, user: nil, severity: nil)
      policies = Ai::InterventionPolicy
        .active
        .for_account(account.id)
        .for_category(action_category)
        .by_specificity

      matching = policies.select { |p| p.matches?(action_category: action_category, agent: agent, user: user) }

      return default_policy if matching.empty?

      # Sort by specificity (most specific wins)
      best = matching.max_by(&:specificity_score)

      # Check severity override: critical always requires_approval unless explicitly auto_approved
      if severity == "critical" && best.policy == "silent"
        return {
          policy: "require_approval",
          channels: best.preferred_channels.presence || %w[notification],
          conditions: best.conditions
        }
      end

      # Check daily notification limit
      if best.policy == "notify_and_proceed" && notification_limit_reached?(best, user)
        return {
          policy: "silent",
          channels: [],
          conditions: best.conditions,
          reason: "Daily notification limit reached"
        }
      end

      {
        policy: best.policy,
        channels: best.preferred_channels.presence || %w[notification],
        conditions: best.conditions
      }
    end

    # Check if an action should be auto-approved based on intervention policies.
    # Used by ExecutionGateService to override requires_approval decisions.
    #
    # @return [Boolean]
    def auto_approve?(action_category:, agent: nil, user: nil)
      result = resolve(action_category: action_category, agent: agent, user: user)
      result[:policy] == "auto_approve"
    end

    # Check if an action should be blocked.
    def blocked?(action_category:, agent: nil, user: nil)
      result = resolve(action_category: action_category, agent: agent, user: user)
      result[:policy] == "block"
    end

    private

    def default_policy
      {
        policy: "require_approval",
        channels: %w[notification],
        conditions: {}
      }
    end

    def notification_limit_reached?(policy, user)
      max_daily = policy.conditions["max_daily_notifications"]
      return false unless max_daily && user

      today_count = Notification
        .where(account_id: account.id, user_id: user.id)
        .where("created_at >= ?", Time.current.beginning_of_day)
        .where(category: "ai")
        .count

      today_count >= max_daily
    end
  end
end
