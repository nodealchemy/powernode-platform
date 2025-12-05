# frozen_string_literal: true

# Test job for verifying worker connectivity and functionality
class TestWorkerJob < BaseJob

  def execute(worker_id, worker_name, options = {})
    PowernodeWorker.application.log_info("TestWorkerJob started for worker: #{worker_name} (#{worker_id})")
    
    start_time = Time.now
    
    begin
      # Simulate some work
      sleep(rand(1.0..3.0))
      
      # Test basic Redis connectivity
      redis_check = test_redis_connectivity
      
      # Test backend API connectivity 
      backend_check = test_backend_connectivity(worker_id)
      
      # Record successful completion
      duration = start_time ? (Time.now - start_time) : 0
      
      result = {
        worker_id: worker_id,
        worker_name: worker_name,
        test_type: options['test_type'] || 'connectivity_test',
        redis_check: redis_check,
        backend_check: backend_check,
        duration_seconds: (duration || 0).to_f.round(2),
        status: 'completed',
        timestamp: Time.now.iso8601
      }
      
      PowernodeWorker.application.log_info("TestWorkerJob completed successfully for worker: #{worker_name}")
      PowernodeWorker.application.log_info("Test results: #{result.to_json}")
      
      # Report success back to backend if configured
      report_test_completion(worker_id, result) if backend_check[:success]
      
      result
      
    rescue => e
      duration = start_time ? (Time.now - start_time) : 0
      error_result = {
        worker_id: worker_id,
        worker_name: worker_name,
        test_type: options['test_type'] || 'connectivity_test',
        status: 'failed',
        error: e.message,
        duration_seconds: (duration || 0).to_f.round(2),
        timestamp: Time.now.iso8601
      }
      
      PowernodeWorker.application.log_error("TestWorkerJob failed for worker: #{worker_name} - #{e.message}")
      
      # Still try to report the failure
      report_test_completion(worker_id, error_result) rescue nil
      
      raise e
    end
  end

  private
  
  def test_redis_connectivity
    PowernodeWorker.application.logger.debug "Testing Redis connectivity..."
    
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
    start_time = Time.now
    
    # Test basic operations
    test_key = "test_worker_job_#{Time.now.to_i}_#{rand(1000)}"
    redis.set(test_key, 'test_value', ex: 10)
    retrieved_value = redis.get(test_key)
    redis.del(test_key)
    
    response_time = ((Time.now - start_time) * 1000).round(2)
    
    if retrieved_value == 'test_value'
      { success: true, response_time_ms: response_time }
    else
      { success: false, error: 'Redis value mismatch', response_time_ms: response_time }
    end
    
  rescue => e
    response_time = start_time ? ((Time.now - start_time) * 1000).round(2) : 0
    { success: false, error: e.message, response_time_ms: response_time }
  end
  
  def test_backend_connectivity(worker_id)
    PowernodeWorker.application.logger.debug "Testing backend API connectivity..."
    
    begin
      api_client = BackendApiClient.new
      start_time = Time.now
      
      # Test health check endpoint
      health_result = api_client.health_check
      response_time = ((Time.now - start_time) * 1000).round(2)
      
      { success: true, response_time_ms: response_time, health: health_result }
    rescue => e
      response_time = start_time ? ((Time.now - start_time) * 1000).round(2) : 0
      { success: false, error: e.message, response_time_ms: response_time }
    end
  end
  
  def report_test_completion(worker_id, result)
    PowernodeWorker.application.logger.debug "Reporting test completion to backend for worker: #{worker_id}"
    
    api_client = BackendApiClient.new
    
    # Try to report the test results back to the backend via internal API
    api_client.post("/api/v1/internal/workers/#{worker_id}/test_results", { test_results: result })
    
    PowernodeWorker.application.log_info("Test results reported to backend successfully")
  rescue => e
    PowernodeWorker.application.log_warn("Failed to report test results to backend: #{e.message}")
    # Don't fail the job if reporting fails
  end
end