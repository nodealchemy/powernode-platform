# frozen_string_literal: true

module Devops
  # Processes incoming Gitea webhooks
  # Queue: devops_webhooks
  # Retry: 3
  class WebhookHandlerJob < BaseJob
    sidekiq_options queue: "devops_webhooks", retry: 3

    # Process incoming webhook event
    # @param webhook_event_id [String] The webhook event ID
    def execute(webhook_event_id)
      log_info "Processing webhook event", webhook_event_id: webhook_event_id

      # Fetch webhook event data
      event = fetch_webhook_event(webhook_event_id)

      # Update event status to processing
      update_event_status(webhook_event_id, "processing")

      # Parse event type and payload
      event_type = event["event_type"]
      payload = event["payload"]
      provider_id = event["provider_id"]

      # Find matching pipelines
      matching_pipelines = find_matching_pipelines(provider_id, event_type, payload)

      if matching_pipelines.empty?
        log_info "No matching pipelines found", event_type: event_type
        update_event_status(webhook_event_id, "processed", matched_pipelines: 0)
        return
      end

      log_info "Found matching pipelines",
               count: matching_pipelines.count,
               pipeline_ids: matching_pipelines.map { |p| p["id"] }

      # Create pipeline runs for each matching pipeline
      pipeline_run_ids = matching_pipelines.map do |pipeline|
        create_pipeline_run(pipeline, event_type, payload)
      end

      # Update event status
      update_event_status(
        webhook_event_id,
        "processed",
        matched_pipelines: matching_pipelines.count,
        pipeline_run_ids: pipeline_run_ids
      )

      log_info "Webhook event processed",
               webhook_event_id: webhook_event_id,
               pipeline_runs_created: pipeline_run_ids.count
    rescue StandardError => e
      log_error "Webhook processing failed", e, webhook_event_id: webhook_event_id
      update_event_status(webhook_event_id, "failed", error_message: e.message)
      raise
    end

    private

    def fetch_webhook_event(webhook_event_id)
      response = api_client.get("/api/v1/internal/devops/webhook_events/#{webhook_event_id}")
      response.dig("data", "webhook_event")
    end

    def update_event_status(webhook_event_id, status, **attributes)
      api_client.patch("/api/v1/internal/devops/webhook_events/#{webhook_event_id}", {
        webhook_event: { status: status }.merge(attributes)
      })
    end

    def find_matching_pipelines(provider_id, event_type, payload)
      # Fetch all active pipelines for the provider
      response = api_client.get("/api/v1/internal/devops/pipelines", {
        provider_id: provider_id,
        is_active: true
      })

      pipelines = response.dig("data", "pipelines") || []

      # Filter to pipelines that match this event
      pipelines.select do |pipeline|
        matches_trigger?(pipeline, event_type, payload)
      end
    end

    def matches_trigger?(pipeline, event_type, payload)
      triggers = pipeline["triggers"] || {}

      case event_type
      when "pull_request"
        triggers["pull_request"].present? &&
          Array(triggers["pull_request"]).include?(payload["action"])
      when "push"
        return false unless triggers["push"].present?

        ref = payload["ref"]
        return false unless ref

        branch = ref.sub("refs/heads/", "")
        branches = Array(triggers.dig("push", "branches"))

        branches.empty? || branches.any? { |pattern| branch_matches?(branch, pattern) }
      when "issues"
        triggers["issues"].present? &&
          Array(triggers["issues"]).include?(payload["action"])
      when "issue_comment"
        return false unless triggers["issue_comment"].present?

        # Check for @claude mention if configured
        if triggers.dig("issue_comment", "mention_required")
          body = payload.dig("comment", "body") || ""
          return body.match?(/@claude/i)
        end

        Array(triggers["issue_comment"]).include?(payload["action"])
      when "release"
        triggers["release"].present? &&
          Array(triggers["release"]).include?(payload["action"])
      else
        false
      end
    end

    def branch_matches?(branch, pattern)
      if pattern.include?("*")
        # Glob-style pattern
        regex = Regexp.new("^#{pattern.gsub('*', '.*')}$")
        branch.match?(regex)
      else
        branch == pattern
      end
    end

    def create_pipeline_run(pipeline, event_type, payload)
      trigger_context = build_trigger_context(event_type, payload)

      response = api_client.post("/api/v1/internal/devops/pipeline_runs", {
        pipeline_run: {
          pipeline_id: pipeline["id"],
          status: "pending",
          trigger_type: "webhook",
          trigger_context: trigger_context
        }
      })

      pipeline_run_id = response.dig("data", "pipeline_run", "id")

      # Queue pipeline execution
      PipelineExecutionJob.perform_async(pipeline_run_id)

      pipeline_run_id
    end

    def build_trigger_context(event_type, payload)
      context = {
        event_type: event_type,
        received_at: Time.current.iso8601
      }

      case event_type
      when "pull_request"
        pr = payload["pull_request"] || {}
        context.merge!(
          pr_number: pr["number"],
          pr_title: pr["title"],
          pr_action: payload["action"],
          head_sha: pr.dig("head", "sha"),
          head_branch: pr.dig("head", "ref"),
          base_branch: pr.dig("base", "ref"),
          repository: payload.dig("repository", "full_name")
        )
      when "push"
        context.merge!(
          ref: payload["ref"],
          before: payload["before"],
          after: payload["after"],
          commits: (payload["commits"] || []).take(10).map { |c| { sha: c["id"], message: c["message"] } },
          repository: payload.dig("repository", "full_name")
        )
      when "issues"
        issue = payload["issue"] || {}
        context.merge!(
          issue_number: issue["number"],
          issue_title: issue["title"],
          issue_action: payload["action"],
          labels: (issue["labels"] || []).map { |l| l["name"] },
          repository: payload.dig("repository", "full_name")
        )
      when "issue_comment"
        comment = payload["comment"] || {}
        context.merge!(
          issue_number: payload.dig("issue", "number"),
          comment_id: comment["id"],
          comment_body: comment["body"],
          repository: payload.dig("repository", "full_name")
        )
      when "release"
        release = payload["release"] || {}
        context.merge!(
          tag_name: release["tag_name"],
          release_name: release["name"],
          prerelease: release["prerelease"],
          repository: payload.dig("repository", "full_name")
        )
      end

      context
    end
  end
end
