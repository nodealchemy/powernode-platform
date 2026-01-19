# frozen_string_literal: true

# Stub job class for enqueuing report generation to worker service
# Actual implementation is in worker/app/jobs/reports/generate_report_job.rb
class GenerateReportJob < ApplicationJob
  queue_as :reports

  # This stub is for enqueuing only - actual execution happens in worker
  def perform(report_request_id)
    Rails.logger.info("[GenerateReportJob] Enqueued report #{report_request_id} for worker processing")
  end
end
