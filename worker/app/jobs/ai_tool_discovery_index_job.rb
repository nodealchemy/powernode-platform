# frozen_string_literal: true

class AiToolDiscoveryIndexJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 2

  CIRCUIT_BREAKER_TIMEOUT = 120

  def execute(params = {})
    action = params["action"] || "index_all"
    account_id = params["account_id"]

    case action
    when "index_all"
      index_all_accounts
    when "index_account"
      index_account(account_id) if account_id
    else
      log_info("Unknown action: #{action}")
    end
  end

  private

  def index_all_accounts
    log_info("Starting tool discovery indexing for all accounts")

    accounts = fetch_active_accounts
    indexed_count = 0

    accounts.each do |account|
      result = index_account_via_api(account["id"])
      indexed_count += 1 if result
    rescue StandardError => e
      log_error("Failed to index tools for account #{account['id']}: #{e.message}")
    end

    log_info("Tool discovery indexing complete: #{indexed_count}/#{accounts.size} accounts indexed")
  end

  def index_account(account_id)
    log_info("Indexing tools for account #{account_id}")
    index_account_via_api(account_id)
  end

  def index_account_via_api(account_id)
    with_backend_api_circuit_breaker do
      response = backend_api_client.post(
        "/api/v1/internal/ai/tools/index",
        { account_id: account_id }
      )

      if response.success?
        body = JSON.parse(response.body)
        log_info("Indexed #{body['tools_count']} tools for account #{account_id}")
        true
      else
        log_error("Tool indexing API failed for account #{account_id}: #{response.status}")
        false
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
