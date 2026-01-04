# frozen_string_literal: true

module Integrations
  class IntegrationHealthCheckJob < BaseJob
    sidekiq_options queue: 'integrations',
                    retry: 3,
                    dead: false

    # Execute health checks for integration instances
    # Can be called for a single instance or all active instances
    def execute(instance_id = nil)
      if instance_id
        check_single_instance(instance_id)
      else
        check_all_active_instances
      end
    end

    private

    def check_single_instance(instance_id)
      log_info("Checking health for integration instance", instance_id: instance_id)

      # Fetch instance from backend
      response = api_client.get("/api/v1/integrations/instances/#{instance_id}")

      unless response[:success]
        log_error("Failed to fetch instance", instance_id: instance_id, error: response[:error])
        return
      end

      instance = response[:data][:instance]

      # Skip if not active
      unless instance[:status] == "active"
        log_info("Skipping inactive instance", instance_id: instance_id, status: instance[:status])
        return
      end

      # Perform health check
      health_result = perform_health_check(instance)

      # Update instance health metrics
      update_instance_health(instance_id, health_result)

      # Handle unhealthy instances
      handle_unhealthy_instance(instance_id, health_result) unless health_result[:healthy]

      health_result
    end

    def check_all_active_instances
      log_info("Starting health check for all active integration instances")

      # Fetch all active instances
      page = 1
      total_checked = 0
      total_healthy = 0
      total_unhealthy = 0

      loop do
        response = api_client.get("/api/v1/integrations/instances", {
          status: "active",
          page: page,
          per_page: 50
        })

        break unless response[:success]

        instances = response[:data][:instances] || []
        break if instances.empty?

        instances.each do |instance|
          result = check_single_instance(instance[:id])
          total_checked += 1

          if result && result[:healthy]
            total_healthy += 1
          else
            total_unhealthy += 1
          end
        rescue StandardError => e
          log_error("Failed to check instance health", exception: e, instance_id: instance[:id])
          total_unhealthy += 1
        end

        # Check for more pages
        pagination = response[:data][:pagination]
        break if page >= (pagination[:total_pages] || 1)

        page += 1
      end

      log_info("Health check completed",
               total_checked: total_checked,
               healthy: total_healthy,
               unhealthy: total_unhealthy)

      track_cleanup_metrics(
        integration_health_checked: total_checked,
        integration_healthy: total_healthy,
        integration_unhealthy: total_unhealthy
      )

      { checked: total_checked, healthy: total_healthy, unhealthy: total_unhealthy }
    end

    def perform_health_check(instance)
      template_type = instance.dig(:integration_template, :integration_type)

      # Call the test endpoint which performs connection test
      response = api_client.post("/api/v1/integrations/instances/#{instance[:id]}/test")

      if response[:success] && response[:data][:result][:success]
        {
          healthy: true,
          status: "healthy",
          message: response[:data][:result][:message],
          checked_at: Time.current.iso8601,
          response_time_ms: calculate_response_time(response)
        }
      else
        {
          healthy: false,
          status: "unhealthy",
          error: response[:data]&.dig(:result, :error) || response[:error] || "Health check failed",
          checked_at: Time.current.iso8601
        }
      end
    rescue StandardError => e
      {
        healthy: false,
        status: "error",
        error: e.message,
        checked_at: Time.current.iso8601
      }
    end

    def update_instance_health(instance_id, health_result)
      api_client.patch("/api/v1/integrations/instances/#{instance_id}", {
        instance: {
          health_metrics: {
            last_health_check: health_result[:checked_at],
            health_status: health_result[:status],
            last_error: health_result[:error],
            response_time_ms: health_result[:response_time_ms]
          }
        }
      })
    rescue StandardError => e
      log_error("Failed to update instance health metrics", exception: e, instance_id: instance_id)
    end

    def handle_unhealthy_instance(instance_id, health_result)
      # Get instance details to check consecutive failures
      response = api_client.get("/api/v1/integrations/instances/#{instance_id}")
      return unless response[:success]

      instance = response[:data][:instance]
      health_metrics = instance[:health_metrics] || {}
      consecutive_failures = (health_metrics[:consecutive_failures] || 0) + 1

      # Update consecutive failure count
      api_client.patch("/api/v1/integrations/instances/#{instance_id}", {
        instance: {
          health_metrics: health_metrics.merge(
            consecutive_failures: consecutive_failures,
            last_failure_at: Time.current.iso8601
          )
        }
      })

      # Auto-pause after 3 consecutive failures
      if consecutive_failures >= 3
        log_warn("Auto-pausing integration after consecutive failures",
                 instance_id: instance_id,
                 consecutive_failures: consecutive_failures)

        api_client.post("/api/v1/integrations/instances/#{instance_id}/deactivate")

        # Track metric
        increment_counter("integration_auto_paused", instance_id: instance_id)
      end
    end

    def calculate_response_time(response)
      # If response includes timing, use it; otherwise estimate
      response.dig(:data, :result, :response_time_ms) || 0
    end
  end
end
