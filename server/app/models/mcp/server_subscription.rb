# frozen_string_literal: true

# MCP Server Subscription Model - Account subscriptions to hosted servers
#
# Manages marketplace subscriptions to MCP servers.
#
module Mcp
  class ServerSubscription < ApplicationRecord
    self.table_name = "mcp_server_subscriptions"

    # Associations
    belongs_to :account
    belongs_to :hosted_server, class_name: "Mcp::HostedServer"

    # Validations
    validates :status, presence: true, inclusion: {
      in: %w[active paused cancelled expired]
    }
    validates :subscription_type, presence: true, inclusion: {
      in: %w[free trial monthly annual]
    }
    validates :hosted_server_id, uniqueness: { scope: :account_id }
    validates :subscribed_at, presence: true

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :for_account, ->(account) { where(account: account) }
    scope :for_server, ->(server) { where(hosted_server: server) }
    scope :expiring_soon, ->(within = 7.days) {
      where("expires_at IS NOT NULL AND expires_at <= ?", within.from_now)
        .where(status: "active")
    }

    # Callbacks
    before_validation :set_subscribed_at, on: :create

    # Instance methods
    def active?
      status == "active" && (expires_at.nil? || expires_at > Time.current)
    end

    def can_make_request?
      return false unless active?
      return true if monthly_request_limit.nil?
      requests_used_this_month < monthly_request_limit
    end

    def increment_usage!
      increment!(:requests_used_this_month)
    end

    def usage_percentage
      return 0 if monthly_request_limit.nil? || monthly_request_limit.zero?
      (requests_used_this_month.to_f / monthly_request_limit * 100).round(2)
    end

    def remaining_requests
      return nil if monthly_request_limit.nil?
      [monthly_request_limit - requests_used_this_month, 0].max
    end

    def reset_monthly_usage!
      update!(
        requests_used_this_month: 0,
        current_period_start: Time.current,
        current_period_end: 1.month.from_now
      )
    end

    def pause!
      update!(status: "paused")
    end

    def resume!
      return false unless status == "paused"
      update!(status: "active")
    end

    def cancel!
      update!(
        status: "cancelled",
        cancelled_at: Time.current
      )
    end

    def summary
      {
        id: id,
        account_id: account_id,
        hosted_server_id: hosted_server_id,
        server_name: hosted_server.name,
        status: status,
        subscription_type: subscription_type,
        monthly_price_usd: monthly_price_usd&.to_f,
        monthly_request_limit: monthly_request_limit,
        requests_used_this_month: requests_used_this_month,
        usage_percentage: usage_percentage,
        remaining_requests: remaining_requests,
        current_period_start: current_period_start,
        current_period_end: current_period_end,
        subscribed_at: subscribed_at,
        expires_at: expires_at
      }
    end

    private

    def set_subscribed_at
      self.subscribed_at ||= Time.current
    end
  end
end
