# frozen_string_literal: true

class AiProposalExpiryJob < BaseJob
  sidekiq_options queue: :maintenance, retry: 1

  def execute(args = {})
    response = api_client.post("/api/v1/internal/ai/proposals/expire_overdue")

    if response["success"]
      data = response["data"] || {}
      expired = data["expired_count"] || 0
      log_info "[AiProposalExpiryJob] Expired #{expired} overdue proposals" if expired > 0
      data
    else
      log_warn "[AiProposalExpiryJob] API returned error: #{response['error']}"
      { expired_count: 0 }
    end
  end
end
