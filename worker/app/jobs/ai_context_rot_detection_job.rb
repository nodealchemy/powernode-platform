# frozen_string_literal: true

class AiContextRotDetectionJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(params = {})
    action = params["action"] || "detect_all"
    account_id = params["account_id"]
    auto_archive = params["auto_archive"] || false

    case action
    when "detect_all"
      detect_all_accounts(auto_archive: auto_archive)
    when "detect_account"
      detect_account(account_id, auto_archive: auto_archive) if account_id
    else
      log_info("Unknown action: #{action}")
    end
  end

  private

  def detect_all_accounts(auto_archive: false)
    log_info("Starting context rot detection for all accounts")

    accounts = fetch_active_accounts
    total_stale = 0
    total_archived = 0

    accounts.each do |account|
      result = detect_account_via_api(account["id"], auto_archive: auto_archive)
      total_stale += (result&.dig("stale_count") || 0)
      total_archived += (result&.dig("archived") || 0)
    rescue StandardError => e
      log_error("Rot detection failed for account #{account['id']}: #{e.message}")
    end

    log_info("Rot detection complete: #{total_stale} stale entries found, #{total_archived} archived")
  end

  def detect_account(account_id, auto_archive: false)
    log_info("Detecting context rot for account #{account_id}")
    detect_account_via_api(account_id, auto_archive: auto_archive)
  end

  def detect_account_via_api(account_id, auto_archive: false)
    with_backend_api_circuit_breaker do
      response = backend_api_client.post(
        "/api/v1/internal/ai/context/rot-report",
        { account_id: account_id, auto_archive: auto_archive }
      )

      if response.success?
        body = JSON.parse(response.body)
        log_info("Account #{account_id}: #{body['stale_count']} stale, #{body['archived'] || 0} archived")
        body
      else
        log_error("Rot detection API failed for account #{account_id}: #{response.status}")
        nil
      end
    end
  end

  def fetch_active_accounts
    with_backend_api_circuit_breaker do
      response = backend_api_client.get("/api/v1/internal/accounts/active")
      return [] unless response.success?

      JSON.parse(response.body)["accounts"] || []
    end
  rescue StandardError => e
    log_error("Failed to fetch active accounts: #{e.message}")
    []
  end
end
