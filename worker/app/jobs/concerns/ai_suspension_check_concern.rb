# frozen_string_literal: true

# Checks whether AI activity is suspended for the given account.
# Uses the backend API (workers may use a different Redis than the server).
# Caches the result in worker-local Redis for 30 seconds to avoid hammering
# the API on every single job execution.
#
# Worker jobs include this and call `bail_if_ai_suspended!(account_id)` at
# the start of execution, after they have resolved the account context.
module AiSuspensionCheckConcern
  extend ActiveSupport::Concern

  AI_SUSPENSION_CACHE_TTL = 30 # seconds

  # Check if AI is suspended for the account via the backend API.
  # Caches the result in worker-local Redis for AI_SUSPENSION_CACHE_TTL seconds.
  #
  # @param account_id [String] UUID of the account
  # @return [Boolean]
  def ai_suspended?(account_id)
    return false if account_id.blank?

    cache_key = "ai_suspension_check:#{account_id}"

    # Check local cache first
    cached = Sidekiq.redis { |conn| conn.get(cache_key) }
    return cached == "1" unless cached.nil?

    # Call backend API
    suspended = check_suspension_via_api(account_id)

    # Cache the result locally
    Sidekiq.redis do |conn|
      conn.setex(cache_key, AI_SUSPENSION_CACHE_TTL, suspended ? "1" : "0")
    end

    suspended
  rescue StandardError => e
    log_warn("Failed to check AI suspension status: #{e.message}")
    false
  end

  # Call this at the start of execute() after resolving account context.
  # Logs a warning and returns true if suspended (caller should bail).
  #
  # @param account_id [String]
  # @return [Boolean] true if suspended and job should bail
  def bail_if_ai_suspended!(account_id)
    if ai_suspended?(account_id)
      log_info("Skipping execution — AI activity suspended for account #{account_id} (kill switch active)")
      true
    else
      false
    end
  end

  private

  def check_suspension_via_api(account_id)
    response = api_client.get("/api/v1/internal/ai/kill_switch/check", { account_id: account_id })
    response.dig("data", "suspended") == true
  rescue StandardError => e
    log_warn("Kill switch API check failed, assuming not suspended: #{e.message}")
    false
  end
end
