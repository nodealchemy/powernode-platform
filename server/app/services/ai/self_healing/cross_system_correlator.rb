# frozen_string_literal: true

module Ai
  module SelfHealing
    class CrossSystemCorrelator
      CORRELATION_WINDOW = 30.minutes

      def initialize(account:)
        @account = account
      end

      def correlate_failures(time_range: 1.hour)
        ai_failures = recent_ai_failures(time_range)
        devops_events = recent_devops_events(time_range)

        correlations = []

        ai_failures.each do |failure|
          matching_events = devops_events.select do |event|
            temporal_match?(failure[:occurred_at], event[:occurred_at]) &&
              causal_candidate?(failure, event)
          end

          next if matching_events.empty?

          correlations << {
            ai_failure: failure,
            correlated_devops_events: matching_events,
            confidence: calculate_confidence(failure, matching_events),
            suggested_cause: infer_cause(failure, matching_events)
          }
        end

        correlations.sort_by { |c| -c[:confidence] }
      end

      def devops_health
        {
          pipeline_success_rate: pipeline_success_rate,
          git_provider_connectivity: git_provider_connectivity,
          container_quota_utilization: container_quota_utilization,
          recent_deployments: recent_deployments
        }
      end

      private

      def recent_ai_failures(time_range)
        Ai::ExecutionEvent.by_account(@account.id)
                          .with_errors
                          .in_time_range(time_range.ago)
                          .limit(100)
                          .map do |event|
          {
            id: event.id,
            source_type: event.source_type,
            source_id: event.source_id,
            error_class: event.error_class,
            error_message: event.error_message,
            occurred_at: event.created_at
          }
        end
      end

      def recent_devops_events(time_range)
        events = []

        Devops::PipelineRun.where("created_at >= ?", time_range.ago)
                           .joins(:pipeline)
                           .where(ci_cd_pipelines: { account_id: @account.id })
                           .each do |run|
          events << {
            type: "pipeline_run",
            id: run.id,
            status: run.status,
            name: run.pipeline.name,
            occurred_at: run.started_at || run.created_at,
            trigger_type: run.trigger_type
          }
        end

        Devops::ContainerInstance.where(account: @account)
                                 .where("created_at >= ?", time_range.ago)
                                 .each do |container|
          events << {
            type: "container",
            id: container.id,
            status: container.status,
            occurred_at: container.started_at || container.created_at
          }
        end

        events
      end

      def temporal_match?(time_a, time_b)
        return false unless time_a && time_b

        (time_a - time_b).abs <= CORRELATION_WINDOW.to_i
      end

      def causal_candidate?(failure, event)
        event[:occurred_at] && failure[:occurred_at] &&
          event[:occurred_at] <= failure[:occurred_at]
      end

      def calculate_confidence(failure, matching_events)
        score = 0.0

        matching_events.each do |event|
          # Temporal proximity increases confidence
          time_diff = (failure[:occurred_at] - event[:occurred_at]).abs
          score += 0.3 * (1.0 - [time_diff / CORRELATION_WINDOW.to_f, 1.0].min)

          # Failed events are more likely causal
          score += 0.2 if %w[failure failed cancelled timeout].include?(event[:status])

          # Deployment events are high-value signals
          score += 0.2 if event[:trigger_type] == "push"
        end

        [score, 1.0].min.round(2)
      end

      def infer_cause(failure, matching_events)
        failed_pipelines = matching_events.select { |e| e[:type] == "pipeline_run" && e[:status] == "failure" }
        failed_containers = matching_events.select { |e| e[:type] == "container" && %w[failed timeout].include?(e[:status]) }

        if failed_pipelines.any?
          "Pipeline failure (#{failed_pipelines.first[:name]}) may have caused downstream AI failure"
        elsif failed_containers.any?
          "Container failure may have impacted AI execution"
        else
          "Temporal correlation with DevOps activity"
        end
      end

      def pipeline_success_rate
        runs = Devops::PipelineRun.joins(:pipeline)
                                   .where(ci_cd_pipelines: { account_id: @account.id })
                                   .where("ci_cd_pipeline_runs.created_at >= ?", 24.hours.ago)
        return 100.0 if runs.count.zero?

        (runs.where(status: "success").count.to_f / runs.count * 100).round(1)
      end

      def git_provider_connectivity
        Devops::GitProviderCredential.where(account: @account).active.map do |cred|
          {
            provider: cred.provider&.name,
            healthy: cred.healthy?,
            consecutive_failures: cred.consecutive_failures
          }
        end
      end

      def container_quota_utilization
        active = Devops::ContainerInstance.where(account: @account, status: "running").count
        { active_containers: active }
      end

      def recent_deployments
        Devops::PipelineRun.joins(:pipeline)
                           .where(ci_cd_pipelines: { account_id: @account.id })
                           .where(trigger_type: %w[push release])
                           .where("ci_cd_pipeline_runs.created_at >= ?", 24.hours.ago)
                           .order(created_at: :desc)
                           .limit(10)
                           .map do |run|
          {
            pipeline_name: run.pipeline.name,
            status: run.status,
            trigger_type: run.trigger_type,
            started_at: run.started_at
          }
        end
      end
    end
  end
end
