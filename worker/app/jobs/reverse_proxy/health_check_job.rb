# frozen_string_literal: true

require_relative '../base_job'

# Asynchronous health checking for reverse proxy services
# Performs health checks across all configured services
class ReverseProxy::HealthCheckJob < BaseJob
  sidekiq_options queue: 'reverse_proxy',
                  retry: 1

  def execute(environment = nil, specific_service = nil, job_id: nil)
    logger.info "Starting health checks (job: #{job_id}, env: #{environment}, service: #{specific_service})"

    start_time = Time.current
    check_results = {}

    begin
      # Perform health checks via API
      health_result = with_api_retry do
        api_client.post('/api/v1/internal/reverse_proxy/health_check', {
          environment: environment,
          service: specific_service
        })
      end

      check_results = health_result['services'] || {}
      healthy_count = check_results.count { |_, status| status['status'] == 'healthy' }
      total_count = check_results.length
      duration = Time.current - start_time

      overall_status = calculate_overall_status(check_results)

      result = {
        job_id: job_id,
        status: 'completed',
        environment: environment || 'all',
        services: check_results,
        healthy_count: healthy_count,
        total_count: total_count,
        overall_status: overall_status,
        duration: duration.round(2),
        message: "Health check completed: #{healthy_count}/#{total_count} services healthy"
      }

      logger.info "Health check completed: #{healthy_count}/#{total_count} healthy in #{duration.round(2)}s"

      # Update job status via API
      update_job_status(job_id, result) if job_id

      result

    rescue StandardError => e
      duration = Time.current - start_time
      error_result = {
        job_id: job_id,
        status: 'failed',
        error: e.message,
        services: check_results,
        duration: duration.round(2),
        message: 'Health check failed'
      }

      logger.error "Health check failed after #{duration.round(2)}s: #{e.message}"
      
      # Update job status via API
      update_job_status(job_id, error_result) if job_id

      raise e
    end
  end

  private

  def calculate_overall_status(check_results)
    return 'unknown' if check_results.empty?

    healthy = check_results.count { |_, status| status['status'] == 'healthy' }
    total = check_results.length

    if healthy == total
      'healthy'
    elsif healthy > 0
      'degraded'
    else
      'unhealthy'
    end
  end

  def update_job_status(job_id, result)
    api_client.patch("/api/v1/internal/jobs/#{job_id}", {
      status: result[:status],
      result: result
    })
  rescue => e
    logger.warn "Failed to update job status: #{e.message}"
  end
end