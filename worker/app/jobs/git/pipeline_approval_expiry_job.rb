# frozen_string_literal: true

module Git
  class PipelineApprovalExpiryJob < BaseJob
    sidekiq_options queue: 'maintenance', retry: 3

    # Expire pending pipeline approvals that have passed their expiry time
    # Runs on a recurring basis (e.g., every minute) to check for expired approvals
    def execute(options = {})
      account_id = options[:account_id] || options["account_id"]

      log_info "Starting pipeline approval expiry check",
               account_id: account_id

      # Check idempotency - prevent duplicate runs within the same minute
      idempotency_key = "approval_expiry:#{Time.current.strftime('%Y%m%d%H%M')}"
      if already_processed?(idempotency_key)
        log_info "Approval expiry check already ran this minute, skipping"
        return { skipped: true, reason: "already_processed" }
      end

      if account_id.present?
        expire_account_approvals(account_id)
      else
        expire_all_pending_approvals
      end
    rescue BackendApiClient::ApiError => e
      log_error "API error during approval expiry check", e
      raise
    end

    private

    def expire_all_pending_approvals
      log_info "Fetching all expired pending approvals"

      response = api_client.post("/api/v1/internal/git/approvals/expire_stale")
      result = response["data"] || {}

      expired_count = result["expired_count"] || 0
      expired_ids = result["expired_ids"] || []

      log_info "Approval expiry completed",
               expired_count: expired_count

      # Notify users about expired approvals if needed
      if expired_count > 0
        notify_expired_approvals(expired_ids)
      end

      # Mark this minute as processed
      mark_processed("approval_expiry:#{Time.current.strftime('%Y%m%d%H%M')}", ttl: 120)

      {
        success: true,
        expired_count: expired_count,
        expired_ids: expired_ids
      }
    end

    def expire_account_approvals(account_id)
      log_info "Expiring approvals for account", account_id: account_id

      response = api_client.post(
        "/api/v1/internal/git/approvals/expire_stale",
        { account_id: account_id }
      )
      result = response["data"] || {}

      expired_count = result["expired_count"] || 0
      expired_ids = result["expired_ids"] || []

      log_info "Account approval expiry completed",
               account_id: account_id,
               expired_count: expired_count

      # Notify users about expired approvals
      if expired_count > 0
        notify_expired_approvals(expired_ids)
      end

      {
        success: true,
        account_id: account_id,
        expired_count: expired_count,
        expired_ids: expired_ids
      }
    end

    def notify_expired_approvals(approval_ids)
      return if approval_ids.empty?

      log_info "Notifying about expired approvals", count: approval_ids.count

      approval_ids.each do |approval_id|
        notify_approval_expired(approval_id)
      rescue StandardError => e
        log_warn "Failed to send expiry notification",
                 approval_id: approval_id,
                 error: e.message
      end
    end

    def notify_approval_expired(approval_id)
      # Fetch approval details
      response = api_client.get("/api/v1/internal/git/approvals/#{approval_id}")
      approval = response["data"]

      return unless approval

      # Get pipeline and repository info
      pipeline_name = approval.dig("pipeline", "name") || "Pipeline"
      repository_name = approval.dig("repository", "full_name") || "Repository"
      environment = approval["environment"] || "production"
      gate_name = approval["gate_name"] || "Approval"

      # Send notification to relevant users
      # This could be the requested_by user or all required_approvers
      requested_by = approval["requested_by"]
      required_approvers = approval["required_approvers"] || []

      notification_data = {
        type: "approval_expired",
        title: "Pipeline Approval Expired",
        message: "The #{gate_name} approval for #{pipeline_name} in #{environment} has expired.",
        approval_id: approval_id,
        pipeline_name: pipeline_name,
        repository_name: repository_name,
        environment: environment,
        gate_name: gate_name
      }

      # Notify the requester
      if requested_by.present?
        send_notification(requested_by["id"], notification_data)
      end

      # Notify required approvers who didn't respond
      required_approvers.each do |approver_id|
        send_notification(approver_id, notification_data)
      end
    end

    def send_notification(user_id, notification_data)
      api_client.post("/api/v1/internal/notifications", {
        user_id: user_id,
        notification_type: notification_data[:type],
        title: notification_data[:title],
        message: notification_data[:message],
        metadata: notification_data
      })
    rescue StandardError => e
      log_warn "Failed to send notification",
               user_id: user_id,
               error: e.message
    end
  end
end
