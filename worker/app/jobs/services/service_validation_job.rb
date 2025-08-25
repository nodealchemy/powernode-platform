# frozen_string_literal: true

require_relative '../base_job'

# Asynchronous service configuration validation
# Validates service configurations for connectivity and compliance
class Services::ServiceValidationJob < BaseJob
  sidekiq_options queue: 'services',
                  retry: 1

  def execute(service_configs, job_id: nil)
    logger.info "Starting service validation (job: #{job_id})"

    start_time = Time.current
    validation_results = {}

    begin
      validate_required_params({ service_configs: service_configs }, :service_configs)

      # Validate services via API
      validation_result = with_api_retry do
        api_client.post('/api/v1/internal/services/validate_services', {
          services: service_configs
        })
      end

      validation_results = validation_result['validations'] || {}
      valid_count = validation_results.count { |_, result| result['valid'] }
      total_count = validation_results.length
      duration = Time.current - start_time

      result = {
        job_id: job_id,
        status: 'completed',
        validations: validation_results,
        valid_count: valid_count,
        total_count: total_count,
        all_valid: valid_count == total_count,
        duration: duration.round(2),
        message: "Service validation completed: #{valid_count}/#{total_count} services valid"
      }

      logger.info "Service validation completed: #{valid_count}/#{total_count} valid in #{duration.round(2)}s"

      # Update job status via API
      update_job_status(job_id, result) if job_id

      result

    rescue StandardError => e
      duration = Time.current - start_time
      error_result = {
        job_id: job_id,
        status: 'failed',
        error: e.message,
        validations: validation_results,
        duration: duration.round(2),
        message: 'Service validation failed'
      }

      logger.error "Service validation failed after #{duration.round(2)}s: #{e.message}"
      
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