# frozen_string_literal: true

class AiPredictiveMonitorJob < BaseJob
  sidekiq_options queue: "ai_workflow_health", retry: 2

  def execute(params = {})
    action = params["action"] || "monitor_all"
    account_id = params["account_id"]

    case action
    when "monitor_all"
      monitor_all_accounts
    when "monitor_account"
      monitor_account(account_id) if account_id
    else
      log_info("Unknown action: #{action}")
    end
  end

  private

  def monitor_all_accounts
    log_info("Starting predictive monitoring for all accounts")

    accounts = fetch_active_accounts
    total_predictions = 0
    total_remediations = 0

    accounts.each do |account|
      result = monitor_account_via_api(account["id"])
      total_predictions += (result&.dig("predictions_count") || 0)
      total_remediations += (result&.dig("remediations_count") || 0)
    rescue StandardError => e
      log_error("Predictive monitoring failed for account #{account['id']}: #{e.message}")
    end

    log_info("Predictive monitoring complete: #{total_predictions} predictions, #{total_remediations} remediations")
  end

  def monitor_account(account_id)
    log_info("Running predictive monitoring for account #{account_id}")
    monitor_account_via_api(account_id)
  end

  def monitor_account_via_api(account_id)
    with_backend_api_circuit_breaker do
      response = backend_api_client.post(
        "/api/v1/internal/ai/self-healing/predict",
        { account_id: account_id }
      )

      if response.success?
        body = JSON.parse(response.body)
        predictions = body["predictions_count"] || 0
        remediations = body["remediations_count"] || 0
        log_info("Account #{account_id}: #{predictions} predictions, #{remediations} remediations")
        body
      else
        log_error("Predictive monitoring API failed for account #{account_id}: #{response.status}")
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
