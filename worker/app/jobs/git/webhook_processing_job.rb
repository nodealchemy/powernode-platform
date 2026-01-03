# frozen_string_literal: true

module Git
  class WebhookProcessingJob < BaseJob
    sidekiq_options queue: 'webhooks', retry: 3

    # Process incoming Git webhook events
    # Handles push, pull_request, workflow_run, and other events
    def execute(event_id)
      log_info "Processing Git webhook event", event_id: event_id

      # Check idempotency
      idempotency_key = "git_webhook:#{event_id}"
      if already_processed?(idempotency_key)
        log_info "Webhook event already processed, skipping", event_id: event_id
        return { skipped: true, reason: "already_processed" }
      end

      # Fetch event from backend
      response = api_client.get("/api/v1/internal/git/webhook_events/#{event_id}")
      event = response["data"]

      unless event
        log_error "Webhook event not found", event_id: event_id
        return { error: "Event not found" }
      end

      # Mark as processing
      api_client.patch("/api/v1/internal/git/webhook_events/#{event_id}/processing")

      # Process based on event type
      result = process_event(event)

      # Mark as processed or failed
      if result[:success]
        api_client.patch(
          "/api/v1/internal/git/webhook_events/#{event_id}/processed",
          { processing_result: result }
        )
        mark_processed(idempotency_key)
        log_info "Webhook event processed successfully", event_id: event_id, event_type: event["event_type"]
      else
        api_client.patch(
          "/api/v1/internal/git/webhook_events/#{event_id}/failed",
          { error_message: result[:error] }
        )
        log_error "Webhook event processing failed", event_id: event_id, error: result[:error]
      end

      result
    rescue BackendApiClient::ApiError => e
      log_error "API error processing webhook", e, event_id: event_id
      raise
    rescue StandardError => e
      log_error "Error processing webhook", e, event_id: event_id

      # Try to mark as failed
      begin
        api_client.patch(
          "/api/v1/internal/git/webhook_events/#{event_id}/failed",
          { error_message: e.message }
        )
      rescue StandardError
        # Ignore errors when marking as failed
      end

      raise
    end

    private

    def process_event(event)
      event_type = event["event_type"]
      payload = event["payload"] || {}

      case event_type
      when "push"
        handle_push_event(event, payload)
      when "pull_request"
        handle_pull_request_event(event, payload)
      when "workflow_run"
        handle_workflow_run_event(event, payload)
      when "workflow_job"
        handle_workflow_job_event(event, payload)
      when "create", "delete"
        handle_ref_event(event, payload)
      when "release"
        handle_release_event(event, payload)
      when "ping"
        handle_ping_event(event, payload)
      else
        handle_generic_event(event, payload)
      end
    end

    def handle_push_event(event, payload)
      repository = event["repository"]
      return { success: true, action: "skipped", reason: "no_repository" } unless repository

      # Trigger commit sync for the repository
      commits = payload["commits"] || []
      ref = payload["ref"]

      log_info "Processing push event",
               repository: repository["full_name"],
               commits_count: commits.count,
               ref: ref

      # Queue repository sync job to update commits
      RepositorySyncJob.perform_async(
        repository["credential_id"],
        repository["id"],
        "commits"
      )

      {
        success: true,
        action: "push_processed",
        commits_count: commits.count,
        ref: ref
      }
    end

    def handle_pull_request_event(event, payload)
      action = payload["action"]
      pr_number = payload.dig("pull_request", "number")
      repository = event["repository"]

      log_info "Processing pull request event",
               action: action,
               pr_number: pr_number,
               repository: repository&.dig("full_name")

      {
        success: true,
        action: "pull_request_#{action}",
        pr_number: pr_number
      }
    end

    def handle_workflow_run_event(event, payload)
      repository = event["repository"]
      return { success: true, action: "skipped", reason: "no_repository" } unless repository

      workflow_run = payload["workflow_run"] || payload
      run_id = workflow_run["id"]
      conclusion = workflow_run["conclusion"]
      status = workflow_run["status"]

      log_info "Processing workflow run event",
               run_id: run_id,
               status: status,
               conclusion: conclusion

      # Sync pipeline status
      PipelineSyncJob.perform_async(
        repository["id"],
        run_id.to_s
      )

      {
        success: true,
        action: "workflow_run_synced",
        run_id: run_id,
        status: status,
        conclusion: conclusion
      }
    end

    def handle_workflow_job_event(event, payload)
      job = payload["workflow_job"] || payload
      job_id = job["id"]
      status = job["status"]
      conclusion = job["conclusion"]

      log_info "Processing workflow job event",
               job_id: job_id,
               status: status,
               conclusion: conclusion

      {
        success: true,
        action: "workflow_job_processed",
        job_id: job_id,
        status: status,
        conclusion: conclusion
      }
    end

    def handle_ref_event(event, payload)
      ref_type = payload["ref_type"]
      ref = payload["ref"]
      repository = event["repository"]

      log_info "Processing ref event",
               event_type: event["event_type"],
               ref_type: ref_type,
               ref: ref

      # Trigger branch sync if branch was created/deleted
      if ref_type == "branch" && repository
        RepositorySyncJob.perform_async(
          repository["credential_id"],
          repository["id"],
          "branches"
        )
      end

      {
        success: true,
        action: "ref_#{event['event_type']}",
        ref_type: ref_type,
        ref: ref
      }
    end

    def handle_release_event(event, payload)
      action = payload["action"]
      release = payload["release"] || {}

      log_info "Processing release event",
               action: action,
               tag_name: release["tag_name"],
               name: release["name"]

      {
        success: true,
        action: "release_#{action}",
        tag_name: release["tag_name"],
        name: release["name"]
      }
    end

    def handle_ping_event(event, payload)
      log_info "Received ping event", zen: payload["zen"]

      {
        success: true,
        action: "ping_acknowledged",
        zen: payload["zen"]
      }
    end

    def handle_generic_event(event, payload)
      log_info "Processing generic webhook event",
               event_type: event["event_type"],
               action: event["action"]

      {
        success: true,
        action: "generic_processed",
        event_type: event["event_type"]
      }
    end
  end
end
