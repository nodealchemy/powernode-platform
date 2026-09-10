# frozen_string_literal: true

module Integrations
  # Schedules integration health probes. The SERVER owns the probe itself, the
  # health derivation and the auto-pause — see
  # Api::V1::Internal::Devops::IntegrationHealthController.
  #
  # This job used to call the operator-auth /api/v1/devops/integration_instances
  # surface (gated on devops.integrations.read). A worker principal is not a
  # user and carries no permissions, so every sweep 4xx'd, logged "endpoint
  # unreachable" and returned `{ skipped: true }`: the health columns were never
  # written, the `integration_health` verb was permanently `{unknown: N}`, and
  # the auto-pause this schedule advertises never ran (audit 2026-09-10, §4.2).
  class IntegrationHealthCheckJob < BaseJob
    sidekiq_options queue: 'integrations',
                    retry: 3,
                    dead: false

    PER_PAGE = 50

    # Probe one integration instance, or sweep every instance the internal
    # endpoint offers (already scoped to ACTIVE instances on this worker's
    # account, so there is no client-side filter to keep in step with it).
    def execute(instance_id = nil)
      instance_id ? probe_instance(instance_id) : sweep
    end

    private

    def probe_instance(instance_id)
      log_info("Probing integration health", instance_id: instance_id)

      response = api_client.post("/api/v1/internal/devops/integration_health/#{instance_id}/probe")
      data = response[:data] || {}

      unless data[:applied]
        log_info("Integration health probe not applied",
                 instance_id: instance_id, reason: data[:reason] || data[:error])
        return { applied: false, reason: data[:reason] || data[:error] }
      end

      if data[:paused]
        log_warn("Integration auto-paused after consecutive failures",
                 instance_id: instance_id,
                 consecutive_failures: data[:consecutive_failures])
      end

      {
        applied: true,
        health_status: data[:health_status],
        consecutive_failures: data[:consecutive_failures],
        paused: data[:paused]
      }
    end

    def sweep
      log_info("Starting integration health sweep")

      page = 1
      checked = healthy = unhealthy = skipped = paused = 0

      loop do
        response = api_client.get("/api/v1/internal/devops/integration_health",
                                  { page: page, per_page: PER_PAGE })
        break unless response[:success]

        instances = response.dig(:data, :instances) || []
        break if instances.empty?

        instances.each do |instance|
          result = probe_instance(instance[:id])
          checked += 1

          if !result[:applied]
            skipped += 1
          elsif result[:health_status] == 'healthy'
            healthy += 1
          else
            unhealthy += 1
          end

          paused += 1 if result[:paused]
        rescue StandardError => e
          log_error("Failed to probe integration health", exception: e, instance_id: instance[:id])
          checked += 1
          skipped += 1
        end

        total_pages = response.dig(:data, :pagination, :total_pages) || 1
        break if page >= total_pages

        page += 1
      end

      log_info("Integration health sweep completed",
               checked: checked, healthy: healthy, unhealthy: unhealthy,
               skipped: skipped, paused: paused)

      track_cleanup_metrics(
        integration_health_checked: checked,
        integration_healthy: healthy,
        integration_unhealthy: unhealthy,
        integration_auto_paused: paused
      )

      { checked: checked, healthy: healthy, unhealthy: unhealthy, skipped: skipped, paused: paused }
    end
  end
end
