# frozen_string_literal: true

class HealthCheckJob < ApplicationJob
  queue_as :maintenance

  def perform(check_type = "comprehensive")
    start_time = Time.current

    begin
      health_data = case check_type
      when "basic"
                      SystemHealthService.check_basic_health
      when "detailed"
                      SystemHealthService.check_detailed_health
      when "comprehensive"
                      SystemHealthService.check_detailed_health
      else
                      SystemHealthService.check_basic_health
      end

      response_time = ((Time.current - start_time) * 1000).round

      # Store health check result
      SystemHealthCheck.create!(
        check_type: check_type,
        overall_status: health_data[:overall_status],
        health_data: health_data,
        response_time_ms: response_time,
        checked_at: Time.current
      )

      Rails.logger.info "Health check (#{check_type}) completed in #{response_time}ms with status: #{health_data[:overall_status]}"
    rescue => e
      Rails.logger.error "Health check job failed: #{e.message}"

      # Store failed health check
      SystemHealthCheck.create!(
        check_type: check_type,
        overall_status: "critical",
        health_data: {
          error: e.message,
          timestamp: Time.current.iso8601,
          overall_status: "critical"
        },
        response_time_ms: ((Time.current - start_time) * 1000).round,
        checked_at: Time.current
      )

      raise e
    end
  end
end
