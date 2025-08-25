# frozen_string_literal: true

require_relative '../base_job'

# Asynchronous proxy configuration file generation
# Generates Nginx, Apache, or Traefik configuration files
class ReverseProxy::GenerateConfigJob < BaseJob
  sidekiq_options queue: 'reverse_proxy',
                  retry: 2

  def execute(proxy_type, config, job_id: nil)
    logger.info "Starting #{proxy_type} configuration generation (job: #{job_id})"

    start_time = Time.current

    begin
      validate_required_params({ proxy_type: proxy_type, config: config }, :proxy_type, :config)

      # Generate configuration via API
      generation_result = with_api_retry do
        api_client.post('/api/v1/internal/reverse_proxy/generate_config', {
          proxy_type: proxy_type,
          config: config
        })
      end

      duration = Time.current - start_time

      result = {
        job_id: job_id,
        status: 'completed',
        proxy_type: proxy_type,
        config: generation_result['config'],
        filename: generation_result['filename'],
        instructions: generation_result['instructions'],
        size: generation_result['config']&.length || 0,
        duration: duration.round(2),
        message: "#{proxy_type.capitalize} configuration generated successfully"
      }

      logger.info "Generated #{proxy_type} config (#{result[:size]} chars) in #{duration.round(2)}s"

      # Update job status via API
      update_job_status(job_id, result) if job_id

      result

    rescue StandardError => e
      duration = Time.current - start_time
      error_result = {
        job_id: job_id,
        status: 'failed',
        error: e.message,
        proxy_type: proxy_type,
        duration: duration.round(2),
        message: "#{proxy_type.capitalize} configuration generation failed"
      }

      logger.error "Config generation failed after #{duration.round(2)}s: #{e.message}"
      
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