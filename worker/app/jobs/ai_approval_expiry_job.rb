# frozen_string_literal: true

# Drives expiry of overdue Ai::ApprovalRequest rows. Previously no cron drove
# ApprovalRequest#check_expiration!, so requests on the canonical approval seam
# (deferred operations, campaign lands, gateway gates) silently never timed out.
# The server honours each chain's timeout_action (approve/reject/escalate/expire)
# and cascades on_approval_decision to the source.
#
# The same server sweep also settles approved requests whose post-commit
# dispatch never started (IMP-0213523480d1): failed by default, re-dispatched
# only for an operator-allowlisted idempotent category. It signals, and never
# re-runs, a dispatch that started and never finished. Each of those, and a
# stranded request the sweep could not settle, is logged at warn.
class AiApprovalExpiryJob < BaseJob
  sidekiq_options queue: :maintenance, retry: 1

  def execute(args = {})
    response = api_client.post("/api/v1/internal/ai/approval_requests/expire_overdue")

    if response["success"]
      data = response["data"] || {}
      expired = data["expired_count"] || 0
      log_info "[AiApprovalExpiryJob] Expired #{expired} overdue approval requests" if expired > 0
      stranded_failed = data["stranded_failed_count"] || 0
      stranded_redispatched = data["stranded_redispatched_count"] || 0
      if stranded_failed > 0 || stranded_redispatched > 0
        log_warn "[AiApprovalExpiryJob] Settled stranded approval dispatches: " \
                 "#{stranded_failed} failed, #{stranded_redispatched} re-dispatched"
      end
      stranded_errored = data["stranded_errored_count"] || 0
      if stranded_errored > 0
        log_warn "[AiApprovalExpiryJob] #{stranded_errored} stranded approval dispatch(es) could not be settled; " \
                 "they stay owed and are retried next run"
      end
      interrupted = data["interrupted_dispatch_count"] || 0
      if interrupted > 0
        log_warn "[AiApprovalExpiryJob] #{interrupted} approval dispatch(es) started and never finished; " \
                 "their effect is unknown and they were not re-run"
      end
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
