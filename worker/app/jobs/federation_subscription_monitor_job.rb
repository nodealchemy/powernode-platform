# frozen_string_literal: true

# FederationSubscriptionMonitorJob — periodic subscription health sweep.
#
# Ticks hourly via Sidekiq cron. POSTs to the server's worker_api
# endpoint which invokes Federation::SubscriptionMonitorService.run!.
# That service performs three reconciliation passes:
#
#   1. Suspend subscriptions whose FederationGrant has expired
#   2. Retry failed certs past the 30-minute cooldown
#   3. Auto-cancel subscriptions suspended for more than 30 days
#
# Plan reference: Decentralized Federation §L + P4.6.6.
class FederationSubscriptionMonitorJob < BaseJob
  sidekiq_options queue: :system, retry: 1

  def execute(args = {})
    log_info "[FederationSubscriptionMonitorJob] Starting subscription monitor sweep"

    response = api_client.post("/api/v1/system/worker_api/federation/subscription_monitor", {})

    if response["success"]
      data = response["data"] || {}
      log_info "[FederationSubscriptionMonitorJob] sweep complete: " \
               "suspended=#{data['suspended_count']} " \
               "cert_retried=#{data['cert_retried_count']} " \
               "auto_cancelled=#{data['auto_cancelled_count']}"
      data
    else
      log_warn "[FederationSubscriptionMonitorJob] sweep API returned non-success: #{response.inspect}"
      { suspended: 0, error: response["error"] }
    end
  rescue StandardError => e
    log_error "[FederationSubscriptionMonitorJob] sweep failed", e
    raise
  end
end
