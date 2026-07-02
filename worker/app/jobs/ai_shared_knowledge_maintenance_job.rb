# frozen_string_literal: true

# Daily shared-knowledge maintenance with bounded backlog draining.
#
# The server's shared_maintenance endpoint caps each call (learning import,
# quality recalculation, and embedding backfill each process a bounded batch
# within the worker HTTP timeout) and reports `remaining` per step. A single
# daily pass can therefore never drain a multi-thousand backlog — observed
# live as ~92% of shared knowledge stuck stale. This job chains follow-up
# passes while the server reports remaining backlog, rate-limited by
# CHAIN_DELAY_SECONDS between passes and hard-capped at MAX_PASSES per day
# (the daily cron restarts the chain at pass 1).
class AiSharedKnowledgeMaintenanceJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  # 40 passes/day x (>=200 quality recalcs + imports + backfills) per pass
  # comfortably drains a ~6k backlog in one daily chain while keeping each
  # HTTP call small enough to finish inside the backend API timeout.
  MAX_PASSES = 40
  CHAIN_DELAY_SECONDS = 60

  def execute(pass = 1)
    pass = pass.to_i.clamp(1, MAX_PASSES)
    log_info("[SharedKnowledgeMaintenance] Starting shared knowledge maintenance", pass: pass)

    response = with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/memory/shared_maintenance")
    end

    remaining = remaining_backlog(response)
    log_info("[SharedKnowledgeMaintenance] Maintenance pass completed", pass: pass, remaining: remaining)

    chain_next_pass(pass, remaining)

    run_quality_audit
  end

  private

  # Sum of unprocessed rows reported by each bounded maintenance step.
  def remaining_backlog(response)
    data = response.is_a?(Hash) ? (response["data"] || response) : {}
    return 0 unless data.is_a?(Hash)

    %w[import_result quality_recalc embedding_backfill].sum do |step|
      step_result = data[step]
      step_result.is_a?(Hash) ? step_result["remaining"].to_i : 0
    end
  end

  def chain_next_pass(pass, remaining)
    return unless remaining.positive?

    if pass < MAX_PASSES
      self.class.perform_in(CHAIN_DELAY_SECONDS, pass + 1)
      log_info("[SharedKnowledgeMaintenance] Backlog remaining — chained follow-up pass",
               next_pass: pass + 1, remaining: remaining, delay_seconds: CHAIN_DELAY_SECONDS)
    else
      log_warn("[SharedKnowledgeMaintenance] Pass cap reached with backlog remaining — will resume on next scheduled run",
               pass: pass, remaining: remaining)
    end
  end

  def run_quality_audit
    log_info("[SharedKnowledgeMaintenance] Running knowledge quality audit")

    response = with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/memory/shared_knowledge", params: { per_page: 1 })
    end

    # Log quality audit summary from the maintenance results
    # The server-side shared_maintenance endpoint handles recalculation,
    # so this audit step provides visibility into the post-maintenance state
    stats = response.dig("data", "stats") || response.dig("stats") || {}
    total = stats["total_entries"] || stats["total"] || 0
    avg_quality = stats["avg_quality_score"] || 0

    log_info("[SharedKnowledgeMaintenance] Quality audit complete",
             total_entries: total,
             avg_quality_score: avg_quality)
  rescue StandardError => e
    # Quality audit is non-critical — log and continue
    log_warn("[SharedKnowledgeMaintenance] Quality audit failed (non-critical): #{e.message}")
  end
end
