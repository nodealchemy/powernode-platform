# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class CodeChangeSensor < Base
        def sensor_type
          "code_changes"
        end

        def collect
          observations = []

          # Check for recent git events (PRs, pushes)
          recent_events = recent_git_events
          recent_events.each do |event|
            obs = build_observation(
              title: "Git event: #{event[:event_type]} on #{event[:repo_name]}",
              observation_type: event[:needs_review] ? "request" : "opportunity",
              severity: "info",
              data: event,
              requires_action: event[:needs_review],
              expires_in: 8.hours
            )
            observations << obs if obs
          end

          # Check for failed pipeline runs
          failed_pipelines = recent_failed_pipelines
          failed_pipelines.each do |pipeline|
            obs = build_observation(
              title: "Pipeline failed: #{pipeline[:name]} on #{pipeline[:repo_name]}",
              observation_type: "alert",
              severity: "warning",
              data: pipeline,
              requires_action: true,
              expires_in: 4.hours
            )
            observations << obs if obs
          end

          observations.compact
        end

        private

        def recent_git_events
          Devops::GitWebhookEvent
            .where(account_id: account.id)
            .where("created_at >= ?", 1.hour.ago)
            .limit(10)
            .map do |event|
              {
                event_id: event.id,
                event_type: event.event_type,
                repo_name: event.repository&.name,
                needs_review: event.event_type.in?(%w[pull_request_opened pull_request_review_requested])
              }
            end
        rescue StandardError
          []
        end

        def recent_failed_pipelines
          Devops::GitPipeline
            .where(account_id: account.id, status: "failed")
            .where("updated_at >= ?", 2.hours.ago)
            .limit(5)
            .map do |pipeline|
              {
                pipeline_id: pipeline.id,
                name: pipeline.name,
                repo_name: pipeline.repository&.name,
                failed_at: pipeline.updated_at&.iso8601
              }
            end
        rescue StandardError
          []
        end
      end
    end
  end
end
