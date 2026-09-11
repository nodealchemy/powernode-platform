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
  #
  # ── STRING KEYS, DELIBERATELY (review F1) ──────────────────────────────────
  # BackendApiClient#get/#post return `response.body` raw
  # (backend_api_client.rb:385-391,483-486) from a connection built with
  # `conn.response :json` and NO `parser_options`, so bodies are parsed with
  # STRING keys. The first cut of this job read them with symbols: every
  # `response[:success]` was nil, the sweep broke out of its loop on the first
  # iteration, issued ZERO probes, and logged "completed" — the very
  # silently-does-nothing shape this increment exists to remove. Only
  # #unwrap_internal symbolizes (`:316,:323`), and #get/#post do not use it.
  #
  # ── THE PROBE IS NOT RETRY-SAFE (review F2) ────────────────────────────────
  # The default connection retries POST up to 5 times on timeout/5xx
  # (`backend_api_client.rb:359-366`). `POST …/probe` has a side effect PER
  # CALL: it increments the failure streak and can auto-pause the row. A
  # completed request whose response was lost would be re-sent, so one real
  # failed probe could post a streak of five and pause an integration well
  # before the operator-configured threshold. It goes through #post_no_retry,
  # which exists for exactly this rule.
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
      log_info('Probing integration health', instance_id: instance_id)

      # post_no_retry, not post: see the class comment (side effect per call).
      #
      # A 404 is an AUTHORIZATION outcome, not a transient failure: the server
      # answers it identically for "gone" and "another account's row"
      # (worker_tenancy.rb:55-58). Re-driving it can never succeed, so it is a
      # skip — the same rule the sweep applies per instance. Without this the
      # single-probe path (execute(instance_id)) raised and burned all three
      # Sidekiq retries on a row that will never be there. Anything else still
      # raises, so a genuinely transient failure is retried.
      response = begin
        api_client.post_no_retry("/api/v1/internal/devops/integration_health/#{instance_id}/probe")
      rescue BackendApiClient::ApiError => e
        raise unless e.status == 404

        log_info('Integration health probe target not visible; skipping', instance_id: instance_id)
        return { applied: false, reason: 'not_found' }
      end
      data = response['data'] || {}

      unless data['applied']
        log_info('Integration health probe not applied',
                 instance_id: instance_id, reason: data['reason'] || data['error'])
        return { applied: false, reason: data['reason'] || data['error'] }
      end

      if data['paused']
        log_warn('Integration auto-paused after consecutive failed probes',
                 instance_id: instance_id,
                 consecutive_probe_failures: data['consecutive_probe_failures'])
      end

      {
        applied: true,
        health_status: data['health_status'],
        consecutive_probe_failures: data['consecutive_probe_failures'],
        paused: data['paused']
      }
    end

    # ── CURSOR, NOT OFFSET (review F5) ─────────────────────────────────────
    # The listed scope is `status: "active"`, and probing MUTATES it: an
    # auto-paused instance leaves the scope, so an offset-paginated page 2
    # shifts left and skips as many rows as page 1 paused. Paginating by an
    # `after` id cursor over a stable `created_at, id` order means a row that
    # leaves the scope takes nothing with it.
    def sweep
      log_info('Starting integration health sweep')

      cursor = nil
      checked = healthy = unhealthy = skipped = paused = 0

      loop do
        params = { per_page: PER_PAGE }
        params[:after] = cursor if cursor

        response = api_client.get('/api/v1/internal/devops/integration_health', params)
        break unless response['success']

        instances = response.dig('data', 'instances') || []
        break if instances.empty?

        instances.each do |instance|
          result = probe_instance(instance['id'])
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
          log_error('Failed to probe integration health', exception: e, instance_id: instance['id'])
          checked += 1
          skipped += 1
        end

        cursor = response.dig('data', 'next_cursor')
        break if cursor.blank?
      end

      log_info('Integration health sweep completed',
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
