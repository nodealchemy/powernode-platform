# frozen_string_literal: true

# Test controller for worker authentication and activity tracking
# Workers authenticate via JWT (type: "worker") through the standard authenticate_request flow
class Api::V1::WorkerTestController < ApplicationController

  # Test endpoint for workers to verify authentication
  def ping
    current_worker.record_activity!("ping_test", {
      endpoint: request.path,
      method: request.request_method,
      timestamp: Time.current.iso8601
    })

    render_success({
      message: "Worker authenticated successfully",
      worker_id: current_worker.id,
      worker_name: current_worker.name,
      request_count: current_worker.request_count,
      timestamp: Time.current.iso8601
    })
  end

  # Test endpoint to simulate job processing
  def process_job
    job_data = params.permit(:job_class, :job_id, args: [], options: {})

    current_worker.record_activity!("job_processing_test", {
      job_class: job_data[:job_class],
      job_id: job_data[:job_id],
      args: job_data[:args],
      options: job_data[:options],
      endpoint: request.path,
      method: request.request_method,
      timestamp: Time.current.iso8601
    })

    render_success({
      message: "Job processing test completed",
      job_data: job_data,
      worker_id: current_worker.id,
      processed_at: Time.current.iso8601
    })
  end
end
