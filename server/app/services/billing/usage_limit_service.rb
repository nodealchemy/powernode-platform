# frozen_string_literal: true

module Billing
  class UsageLimitService
    # Main limit checking methods for each resource type
    def self.can_add_user?(account)
      check_limit(account, "max_users", account.users.count)
    end

    def self.can_create_api_key?(account)
      check_limit(account, "max_api_keys", account.api_keys.active.count)
    end

    def self.can_create_webhook?(account)
      webhook_count = account.webhook_endpoints.where(status: "active").count
      check_limit(account, "max_webhooks", webhook_count)
    end

    def self.can_create_worker?(account)
      check_limit(account, "max_workers", account.workers.count)
    end

    # Helper method to get current usage for a specific limit type
    def self.current_usage(account, limit_type)
      case limit_type
      when "max_users"
        account.users.count
      when "max_api_keys"
        account.api_keys.active.count
      when "max_webhooks"
        account.webhook_endpoints.where(status: "active").count
      when "max_workers"
        account.workers.count
      else
        0
      end
    end

    # Get usage summary for all limits
    def self.usage_summary(account)
      plan = account.subscription&.plan
      return {} unless plan

      %w[max_users max_api_keys max_webhooks max_workers].each_with_object({}) do |limit_type, summary|
        current = current_usage(account, limit_type)
        limit = plan.limits[limit_type] || 0
        is_unlimited = limit >= 999

        summary[limit_type] = {
          current: current,
          limit: limit,
          unlimited: is_unlimited,
          percentage: is_unlimited ? 0 : (current.to_f / limit * 100).round(1),
          available: is_unlimited ? Float::INFINITY : [limit - current, 0].max
        }
      end
    end

    # Check if account has reached any limits
    def self.has_reached_limits?(account)
      summary = usage_summary(account)
      summary.any? { |_, data| !data[:unlimited] && data[:current] >= data[:limit] }
    end

    # Get the specific limit value for a resource type
    def self.get_limit(account, limit_type)
      plan = account.subscription&.plan
      return 0 unless plan

      plan.limits[limit_type] || 0
    end

    private

    def self.check_limit(account, limit_key, current_count)
      plan = account.subscription&.plan
      return false unless plan

      plan_limit = plan.limits[limit_key] || 0
      return true if plan_limit >= 999 # Unlimited threshold

      current_count < plan_limit
    end
  end
end

# Backwards compatibility alias
