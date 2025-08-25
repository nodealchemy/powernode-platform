# frozen_string_literal: true

require_relative '../base_job'

# Asynchronous reverse proxy configuration testing
# Tests proxy configuration validity and service connectivity
class ReverseProxy::TestConfigurationJob < BaseJob
  sidekiq_options queue: 'reverse_proxy',
                  retry: 1

  def execute(test_config, job_id: nil)
    logger.info "Starting reverse proxy configuration test (job: #{job_id})"

    start_time = Time.current

    begin
      # Validate configuration structure via API
      validation_result = with_api_retry do
        api_client.post('/api/v1/internal/reverse_proxy/validate', {
          config: test_config
        })
      end

      # Test service connectivity via API
      connectivity_result = with_api_retry do
        api_client.post('/api/v1/internal/reverse_proxy/test_connectivity', {
          config: test_config
        })
      end

      duration = Time.current - start_time

      result = {
        job_id: job_id,
        status: 'completed',
        validation: validation_result,
        connectivity: connectivity_result,
        duration: duration.round(2),
        message: 'Configuration test completed successfully'
      }

      logger.info "Configuration test completed in #{duration.round(2)}s"

      # Update job status via API
      update_job_status(job_id, result) if job_id

      result

    rescue StandardError => e
      duration = Time.current - start_time
      error_result = {
        job_id: job_id,
        status: 'failed',
        error: e.message,
        duration: duration.round(2),
        message: 'Configuration test failed'
      }

      logger.error "Configuration test failed after #{duration.round(2)}s: #{e.message}"
      
      # Update job status via API
      update_job_status(job_id, error_result) if job_id

      raise e
    end
  end

  private

  def update_job_status(job_id, result)
    api_client.patch("/api/v1/internal/jobs/#{job_id}", {
      status: result[:status],
      result: result
    })
  rescue => e
    logger.warn "Failed to update job status: #{e.message}"
  end
end