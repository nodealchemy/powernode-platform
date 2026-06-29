# frozen_string_literal: true

# Drives expiry of overdue Ai::ApprovalRequest rows. Previously no cron drove
# ApprovalRequest#check_expiration!, so requests on the canonical approval seam
# (deferred operations, campaign lands, gateway gates) silently never timed out.
# The server honours each chain's timeout_action (approve/reject/escalate/expire)
# and cascades on_approval_decision to the source.
class AiApprovalExpiryJob < BaseJob
  sidekiq_options queue: :maintenance, retry: 1

  def execute(args = {})
    response = api_client.post("/api/v1/internal/ai/approval_requests/expire_overdue")

    if response["success"]
      data = response["data"] || {}
      expired = data["expired_count"] || 0
      log_info "[AiApprovalExpiryJob] Expired #{expired} overdue approval requests" if expired > 0
      data
    else
      log_warn "[AiApprovalExpiryJob] API returned error: #{response['error']}"
      { expired_count: 0 }
    end
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("[AiApprovalExpiryJob] Backend unavailable, skipping (will retry next cron)")
  rescue BackendApiClient::ApiError => e
    log_info("[AiApprovalExpiryJob] Skipped: #{e.message}")
  end
end
