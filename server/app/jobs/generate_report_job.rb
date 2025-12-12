# frozen_string_literal: true

# Proxy job class for enqueueing report generation to worker service
# The actual job implementation lives in the worker service
class GenerateReportJob < ApplicationJob
  queue_as :reports

  def perform(report_request_id)
    # This is a proxy job that forwards the request to the worker service
    # The actual GenerateReportJob implementation is in the worker service

    Rails.logger.info "Enqueueing report generation for request #{report_request_id} to worker service"

    # The worker service will pick up this job from the shared Redis queue
    # and execute the real GenerateReportJob implementation

    # Note: This method intentionally does nothing as the worker service
    # handles the actual job execution via the shared Sidekiq queue
  end
end
