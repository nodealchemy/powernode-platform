# frozen_string_literal: true

class TradingPhaseReviewJob < BaseJob
  sidekiq_options queue: 'trading', retry: 1

  def execute
    response = api_client.get("/api/v1/internal/trading/strategies_for_review")
    strategies = response.dig("data", "items") || []

    reviewed = 0
    strategies.each do |strategy|
      phase = strategy["lifecycle_phase"]
      next unless reviewable_phase?(phase)

      recommendation = evaluate_phase(strategy)
      next unless recommendation

      api_client.post("/api/v1/internal/trading/review_phase", {
        strategy_id: strategy["id"],
        current_phase: phase,
        recommendation: recommendation[:action],
        reason: recommendation[:reason]
      })
      reviewed += 1
    rescue StandardError => e
      log_error("Phase review failed for strategy #{strategy['id']}", e)
    end

    log_info("Phase review complete: #{reviewed}/#{strategies.size} reviewed")
    { reviewed: reviewed, total: strategies.size }
  end

  private

  def reviewable_phase?(phase)
    %w[backtest paper_trade live_small live_full matured declining].include?(phase)
  end

  def evaluate_phase(strategy)
    case strategy["lifecycle_phase"]
    when "backtest"
      if (strategy["total_trades"] || 0) >= 50
        { action: "graduate", reason: "Backtest phase complete with #{strategy['total_trades']} simulated trades" }
      end
    when "paper_trade"
      if (strategy["current_pnl_pct"] || 0) > 0 && days_in_phase(strategy) >= 7
        { action: "graduate", reason: "Paper trading profitable for 7+ days" }
      end
    when "live_small"
      pnl = strategy["current_pnl_pct"] || 0
      if pnl > 0 && days_in_phase(strategy) >= 14
        { action: "graduate", reason: "Live small profitable for 14+ days" }
      elsif pnl < -5
        { action: "demote", reason: "Drawdown exceeds -5% in live_small" }
      end
    when "live_full"
      if (strategy["current_pnl_pct"] || 0) < -10
        { action: "demote", reason: "Drawdown exceeds -10% in live_full" }
      end
    when "declining"
      if days_in_phase(strategy) >= 30
        { action: "decommission", reason: "Declining for 30+ days" }
      end
    end
  end

  def days_in_phase(strategy)
    updated = strategy["updated_at"]
    return 0 unless updated

    (Time.current - Time.parse(updated)).to_i / 86400
  end
end
