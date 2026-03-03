# frozen_string_literal: true

module Devops
  class OverviewService
    module CiCdMetrics
      extend ActiveSupport::Concern

      private

      def generate_ci_cd_metrics
        {
          pipelines: pipeline_metrics,
          pipeline_runs: pipeline_run_metrics,
          runners: runner_metrics,
          schedules: schedule_metrics
        }
      end

      def pipeline_metrics
        pipelines = account.devops_pipelines

        {
          total: pipelines.count,
          active: pipelines.active.count
        }
      end

      def pipeline_run_metrics
        runs = Devops::PipelineRun.where(
          devops_pipeline_id: account.devops_pipelines.select(:id)
        )
        today_range = Time.current.beginning_of_day..Time.current.end_of_day

        total = runs.count
        successful = runs.successful.count
        failed = runs.failed.count
        running = runs.running.count
        today = runs.where(created_at: today_range).count

        {
          total: total,
          successful: successful,
          failed: failed,
          running: running,
          today: today,
          success_rate: total > 0 ? (successful.to_f / total * 100).round(1) : 0.0
        }
      end

      def runner_metrics
        runners = account.git_runners

        {
          total: runners.count,
          online: runners.online.count,
          offline: runners.offline.count,
          busy: runners.busy.count
        }
      end

      def schedule_metrics
        schedules = Devops::Schedule.where(
          devops_pipeline_id: account.devops_pipelines.select(:id)
        )

        {
          total: schedules.count,
          active: schedules.active.count
        }
      end
    end
  end
end
