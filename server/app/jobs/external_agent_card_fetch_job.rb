# frozen_string_literal: true

# ExternalAgentCardFetchJob - Fetches and caches agent cards from external A2A agents
class ExternalAgentCardFetchJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff for transient network failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(external_agent_id)
    external_agent = ExternalAgent.find_by(id: external_agent_id)

    unless external_agent
      Rails.logger.warn("[ExternalAgentCardFetchJob] Agent #{external_agent_id} not found, skipping")
      return
    end

    Rails.logger.info("[ExternalAgentCardFetchJob] Fetching agent card for #{external_agent.name} (#{external_agent_id})")

    begin
      # Mark as fetching
      external_agent.update!(
        card_fetch_status: "fetching",
        card_fetch_started_at: Time.current
      )

      # Fetch the agent card
      external_agent.fetch_agent_card!

      # Update success status
      external_agent.update!(
        card_fetch_status: "success",
        card_fetched_at: Time.current,
        card_fetch_error: nil
      )

      Rails.logger.info("[ExternalAgentCardFetchJob] Successfully fetched agent card for #{external_agent.name}")
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      handle_fetch_error(external_agent, "Connection timeout: #{e.message}", retryable: true)
      raise # Re-raise for retry
    rescue Errno::ECONNREFUSED => e
      handle_fetch_error(external_agent, "Connection refused: #{e.message}", retryable: true)
      raise
    rescue JSON::ParserError => e
      handle_fetch_error(external_agent, "Invalid agent card format: #{e.message}", retryable: false)
      # Don't re-raise - invalid format won't fix itself
    rescue StandardError => e
      handle_fetch_error(external_agent, e.message, retryable: true)
      raise
    end
  end

  private

  def handle_fetch_error(external_agent, error_message, retryable:)
    Rails.logger.error("[ExternalAgentCardFetchJob] Failed to fetch agent card for #{external_agent.name}: #{error_message}")

    external_agent.update!(
      card_fetch_status: retryable ? "failed_retrying" : "failed",
      card_fetch_error: error_message,
      card_fetch_attempts: (external_agent.card_fetch_attempts || 0) + 1
    )
  end
end
