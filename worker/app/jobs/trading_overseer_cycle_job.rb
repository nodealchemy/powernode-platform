# frozen_string_literal: true

# Lightweight cron complement to the Ralph-loop-based Trading Overseer (cycle #53).
# Ralph handles AI reasoning; this job runs the PROGRAMMATIC (non-LLM) decision
# engine evaluation — rule-based autonomous actions like temporal pruning,
# capital rebalancing triggers, and strategy lifecycle transitions.
class TradingOverseerCycleJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute
    # Find all accounts with an active trading portfolio
    response = api_client.get("/api/v1/internal/trading/active_portfolios")
    return unless response&.dig("data", "items")

    account_ids = response["data"]["items"].map { |p| p["account_id"] }.uniq

    account_ids.each do |account_id|
      run_decision_cycle(account_id)
    end
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("Backend unavailable, skipping overseer cycle (will retry next cron)")
  rescue BackendApiClient::ApiError => e
    log_info("Overseer cycle skipped: #{e.message}")
  end

  private

  def run_decision_cycle(account_id)
    response = api_client.post("/api/v1/internal/trading/overseer_decision_cycle", {
      account_id: account_id
    })

    if response&.dig("data", "skipped")
      log_info("[OverseerCycle] Account #{account_id[0..7]}: skipped " \
               "(#{response.dig('data', 'reason')}) — next: #{response.dig('data', 'next_scheduled_at')}")
      return
    end

    if response&.dig("data", "decisions_made").to_i > 0
      decisions = response.dig("data", "decisions") || []
      log_info("[OverseerCycle] Account #{account_id[0..7]}: #{decisions.size} decisions — #{decisions.map { |d| "#{d['action']}:#{d['decision']}" }.join(', ')}")
    end
  rescue StandardError => e
    log_warn("[OverseerCycle] Failed for account #{account_id[0..7]}: #{e.message}")
  end
end
