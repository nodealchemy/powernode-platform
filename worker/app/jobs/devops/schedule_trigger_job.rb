# frozen_string_literal: true

module Devops
  # Triggers scheduled pipelines (called by Sidekiq-Cron)
  # Queue: devops_default
  # Retry: 1
  class ScheduleTriggerJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 1

    # Trigger all due scheduled pipelines
    def execute
      log_info "Checking for due scheduled pipelines"

      # Fetch due schedules from backend
      schedules = fetch_due_schedules

      if schedules.empty?
        log_info "No schedules due for execution"
        return
      end

      log_info "Found #{schedules.count} schedules due for execution"

      triggered_count = 0
      error_count = 0

      schedules.each do |schedule|
        trigger_schedule(schedule)
        triggered_count += 1
      rescue StandardError => e
        log_error "Failed to trigger schedule", e, schedule_id: schedule["id"]
        error_count += 1
      end

      log_info "Schedule trigger completed",
               triggered: triggered_count,
               errors: error_count
    end

    private

    def fetch_due_schedules
      response = api_client.get("/api/v1/internal/devops/schedules/due")
      response.dig("data", "schedules") || []
    end

    def trigger_schedule(schedule)
      log_info "Triggering schedule", schedule_id: schedule["id"], pipeline_name: schedule["pipeline_name"]

      # Create pipeline run via API
      response = api_client.post("/api/v1/internal/devops/pipeline_runs", {
        pipeline_run: {
          pipeline_id: schedule["pipeline_id"],
          status: "pending",
          trigger_type: "schedule",
          trigger_context: build_trigger_context(schedule)
        }
      })

      pipeline_run_id = response.dig("data", "pipeline_run", "id")

      # Update schedule with last run time
      update_schedule(schedule["id"])

      # Queue pipeline execution
      PipelineExecutionJob.perform_async(pipeline_run_id)

      log_info "Pipeline run created", pipeline_run_id: pipeline_run_id, schedule_id: schedule["id"]
    end

    def build_trigger_context(schedule)
      {
        schedule_id: schedule["id"],
        schedule_name: schedule["name"],
        cron_expression: schedule["cron_expression"],
        timezone: schedule["timezone"],
        inputs: schedule["inputs"],
        triggered_at: Time.current.iso8601
      }
    end

    def update_schedule(schedule_id)
      api_client.patch("/api/v1/internal/devops/schedules/#{schedule_id}/triggered", {
        schedule: {
          last_run_at: Time.current.iso8601
        }
      })
    end
  end
end
