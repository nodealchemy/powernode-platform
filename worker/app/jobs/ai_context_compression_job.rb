# frozen_string_literal: true

class AiContextCompressionJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(params = {})
    action = params["action"] || "compress_all"
    account_id = params["account_id"]

    case action
    when "compress_all"
      compress_all_accounts
    when "compress_account"
      compress_account(account_id) if account_id
    else
      log_info("Unknown action: #{action}")
    end
  end

  private

  def compress_all_accounts
    log_info("Starting context compression for all accounts")

    accounts = fetch_active_accounts
    total_compressed = 0

    accounts.each do |account|
      result = compress_account_via_api(account["id"])
      total_compressed += (result || 0)
    rescue StandardError => e
      log_error("Compression failed for account #{account['id']}: #{e.message}")
    end

    log_info("Context compression complete: #{total_compressed} entries compressed")
  end

  def compress_account(account_id)
    log_info("Compressing context for account #{account_id}")
    compress_account_via_api(account_id)
  end

  def compress_account_via_api(account_id)
    with_backend_api_circuit_breaker do
      response = backend_api_client.post(
        "/api/v1/internal/ai/context/compress",
        { account_id: account_id }
      )

      if response.success?
        body = JSON.parse(response.body)
        compressed = body["compressed"] || 0
        log_info("Compressed #{compressed} entries for account #{account_id}")
        compressed
      else
        log_error("Compression API failed for account #{account_id}: #{response.status}")
        0
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
