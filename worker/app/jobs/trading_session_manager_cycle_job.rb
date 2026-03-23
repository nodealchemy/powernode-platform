# frozen_string_literal: true

# Training Session Manager cycle: session discovery, scheduling, pruning,
# mid-session actions, and session lifecycle management. Runs every 10 minutes.
#
# This job is the Session Manager agent's scheduling mechanism, distinct from
# the Portfolio Manager's cycle (TradingPortfolioManagerCycleJob).
class TradingSessionManagerCycleJob < BaseJob
  sidekiq_options queue: 'trading_critical', retry: 1

  def execute(args = {})
    if args.is_a?(Hash) && args["account_id"]
      run_session_cycle(args["account_id"])
      return { account_id: args["account_id"] }
    end

    # Find all accounts with an active trading portfolio
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    return unless response&.dig("data", "items")

    account_ids = response["data"]["items"].map { |p| p["account_id"] }.uniq

    log_info("Dispatching session manager cycle for #{account_ids.size} accounts")
    account_ids.each do |account_id|
      TradingSessionManagerCycleJob.perform_async({ "account_id" => account_id })
    end

    { dispatched: account_ids.size }
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("Backend unavailable, skipping session manager cycle (will retry next cron)")
  rescue BackendApiClient::ApiError => e
    log_info("Session manager cycle skipped: #{e.message}")
  end

  private

  def run_session_cycle(account_id)
    response = api_client.post("/api/v1/internal/trading/overseer_decision_cycle", {
      account_id: account_id,
      engine_type: "training"
    })

    if response&.dig("data", "skipped")
      log_info("[SessionManager] Account #{account_id[0..7]}: skipped " \
               "(#{response.dig('data', 'reason')}) — next: #{response.dig('data', 'next_scheduled_at')}")
      return
    end

    if response&.dig("data", "decisions_made").to_i > 0
      decisions = response.dig("data", "decisions") || []
      log_info("[SessionManager] Account #{account_id[0..7]}: #{decisions.size} decisions — " \
               "#{decisions.map { |d| "#{d['action']}:#{d['decision']}" }.join(', ')}")
    end
  rescue StandardError => e
    log_warn("[SessionManager] Failed for account #{account_id[0..7]}: #{e.message}")
  end
end
