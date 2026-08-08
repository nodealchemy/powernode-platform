# frozen_string_literal: true

# Ticks the core OODA closure driver (IMP-e041c835a40d): asks the server which
# accounts are worth a closure cycle, then drives one tick per account. The
# server owns every activation gate (the default-OFF cadence flag, the account
# kill switch, the control-plane fence, per-agent budgets) — when the driver
# is disabled the accounts list comes back empty and this job is a no-op log
# line, so the cron can tick unconditionally.
class AiClosureDriverJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 1

  def execute(_args = {})
    response = api_client.get("/api/v1/internal/ai/closure_driver/accounts")
    account_ids = response["data"] || []

    if account_ids.empty?
      log_info "[AiClosureDriverJob] no eligible accounts (driver disabled or no active goals)"
      return { accounts_processed: 0, cycles_run: 0 }
    end

    cycles_run = 0
    accounts_processed = 0

    account_ids.each do |account_id|
      result = api_client.post("/api/v1/internal/ai/closure_driver/run", { account_id: account_id })
      data = result["data"] || {}
      cycles_run += data["cycles_run"].to_i
      accounts_processed += 1
    rescue StandardError => e
      log_warn "[AiClosureDriverJob] tick failed for account #{account_id}: #{e.message}"
    end

    log_info "[AiClosureDriverJob] #{accounts_processed} account(s), #{cycles_run} cycle(s) run"
    { accounts_processed: accounts_processed, cycles_run: cycles_run }
  end
end
