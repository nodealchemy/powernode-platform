# frozen_string_literal: true

# Generates daily operational summaries for each account.
# Scheduled daily via sidekiq-cron (see worker/config/sidekiq.yml).
# Communicates with the server via HTTP API.
class DailySummaryJob < BaseJob
  sidekiq_options queue: "maintenance", retry: 2

  def execute(account_id = nil)
    if account_id
      generate_for_account(account_id)
    else
      generate_for_all_accounts
    end
  end

  private

  def generate_for_all_accounts
    log_info("Starting daily summary generation for all accounts")

    accounts = fetch_accounts
    return log_info("No accounts found") if accounts.blank?

    generated = 0
    accounts.each do |account|
      generate_for_account(account["id"])
      generated += 1
    rescue StandardError => e
      log_error("Failed to generate summary for account #{account['id']}: #{e.message}")
    end

    log_info("Daily summary generation complete", generated: generated, total: accounts.size)
  end

  def generate_for_account(account_id)
    response = server_post(
      "/api/v1/admin/daily_summaries/generate",
      { date: Date.yesterday.iso8601 },
      account_id: account_id
    )

    if response && response["success"]
      log_info("Generated daily summary", account_id: account_id)
    else
      log_error("Failed to generate daily summary", account_id: account_id, error: response&.dig("error"))
    end
  end

  def fetch_accounts
    response = server_get("/api/v1/admin/accounts")
    response&.dig("data") || []
  rescue StandardError => e
    log_error("Failed to fetch accounts: #{e.message}")
    []
  end
end
