# frozen_string_literal: true

require_relative '../base_job'

# Asynchronous service discovery for reverse proxy
# Discovers services via DNS, Consul, port scanning, or Kubernetes
class ReverseProxy::ServiceDiscoveryJob < BaseJob
  sidekiq_options queue: 'reverse_proxy',
                  retry: 2

  def execute(discovery_config, job_id: nil)
    logger.info "Starting service discovery (job: #{job_id})"

    start_time = Time.current
    discovered_services = []

    begin
      validate_required_params({ discovery_config: discovery_config }, :discovery_config)

      # Run service discovery via API
      discovery_result = with_api_retry do
        api_client.post('/api/v1/internal/reverse_proxy/service_discovery', {
          discovery_config: discovery_config
        })
      end

      discovered_services = discovery_result['services'] || []
      duration = Time.current - start_time

      result = {
        job_id: job_id,
        status: 'completed',
        services: discovered_services,
        services_count: discovered_services.length,
        methods_used: discovery_config['methods'] || [],
        duration: duration.round(2),
        message: "Service discovery completed: #{discovered_services.length} services found"
      }

      logger.info "Service discovery found #{discovered_services.length} services in #{duration.round(2)}s"

      # Update job status via API
      update_job_status(job_id, result) if job_id

      result

    rescue StandardError => e
      duration = Time.current - start_time
      error_result = {
        job_id: job_id,
        status: 'failed',
        error: e.message,
        services: discovered_services,
        services_count: discovered_services.length,
        duration: duration.round(2),
        message: 'Service discovery failed'
      }

      logger.error "Service discovery failed after #{duration.round(2)}s: #{e.message}"
      
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