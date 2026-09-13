# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Devops
        # The integration health sweep's server half (worker:
        # Integrations::IntegrationHealthCheckJob, cron */15).
        #
        # WHY THIS EXISTS. The sweep used to call the OPERATOR-auth
        # `/api/v1/devops/integration_instances*` surface, which gates on
        # `devops.integrations.read`; a worker principal is not a user and
        # carries no permissions, so every sweep got a 4xx, logged "endpoint
        # unreachable" and returned early. The three health columns therefore
        # had no writer at all and `integration_health` reported `{unknown: N}`
        # forever (audit 2026-09-10, §4.2).
        #
        # THE SERVER OWNS THE WHOLE PROBE. The connection test already runs
        # server-side (`Devops::ExecutionService.test_connection` builds the
        # executor), so the worker has nothing to measure: it schedules, the
        # server probes, derives and persists in one request. That also removes
        # the old read-modify-write dance (fetch, PATCH metrics, fetch again,
        # PATCH counters, POST deactivate) in which two concurrent sweeps could
        # lose a failure count.
        #
        # WORKER-RECEIVER DISCIPLINE. Every path returns 2xx. A 500 here would
        # put Sidekiq into a retry storm against an integration that is broken
        # by definition; `applied: false` plus a reason carries the outcome.
        class IntegrationHealthController < InternalBaseController
          include Api::V1::Internal::WorkerTenancy

          MAX_PER_PAGE = 100
          DEFAULT_PER_PAGE = 50

          # GET /api/v1/internal/devops/integration_health
          #
          # The instances this worker may probe: ACTIVE ones on its own account.
          # Filtering here rather than in the job keeps the tenancy anchor and
          # the "what is probeable" rule on the server, where they are enforced.
          #
          # CURSOR, NOT OFFSET (review F5). Probing MUTATES the listed scope —
          # an auto-paused instance leaves `status: "active"` — so an
          # offset-paginated page 2 shifts left and silently skips as many rows
          # as page 1 paused. An `after` cursor over the UUIDv7 primary key is
          # stable under deletion from the scope, and UUIDv7 is time-ordered, so
          # `id` alone is a total order with no tiebreak needed.
          def index
            scope = ::Devops::IntegrationInstance
              .where(account_id: worker_account_id, status: "active")
              .order(:id)
            scope = scope.where("id > ?", params[:after]) if params[:after].present?

            instances = scope.limit(per_page).to_a

            render_success({
              instances: instances.map { |i| { id: i.id, slug: i.slug } },
              # nil ends the sweep: a short page is the last page.
              next_cursor: (instances.size == per_page ? instances.last&.id : nil)
            })
          end

          # POST /api/v1/internal/devops/integration_health/:id/probe
          def probe
            instance = find_instance

            # Deleted between listing and probe, or another account's row — the
            # two are deliberately INDISTINGUISHABLE: a 200 for one and a 404
            # for the other would itself confirm the row exists on another
            # account. 404 for both, which is what the seam's tenancy
            # convention requires (worker_tenancy.rb:55-58: a cross-account
            # lookup must 404, never 403 and never a distinguishable success).
            #
            # This is the one path here that is NOT 2xx, and deliberately so:
            # the worker-receiver rule exists to stop retry storms on
            # PROCESSING errors, not to paper over an authorization outcome.
            # The sweep rescues it per instance and counts it skipped.
            return render_error("Integration instance not found", status: :not_found) unless instance

            # NOT `status:` — `render_success(status:)` is the HTTP status
            # keyword (api_response.rb:16). Passing the row's status there
            # raised "Invalid HTTP status", the rescue below turned it into
            # `applied: false, error: ...`, and the worker — which reads
            # `data["applied"]` — saw every probe as not-applied. Caught by the
            # tenancy sweep's positive control, which asserts on the BODY;
            # every other example asserted the ROW and could not see it.
            unless instance.status == "active"
              return render_success(applied: false, reason: "not_active", instance_status: instance.status)
            end

            result = ::Devops::ExecutionService.test_connection(instance: instance)
            paused = instance.record_health_probe!(
              success: result[:success],
              error: result[:message],
              metrics: { "last_probe_at" => Time.current.iso8601 }.compact
            )

            render_success(
              applied: true,
              # Echoed so a worker log line names the integration rather than a
              # bare UUID. Only ever this worker's own account's row: a
              # foreign id 404s above before reaching here.
              name: instance.name,
              slug: instance.slug,
              health_status: instance.health_status,
              # The PROBE streak, not the execution streak — they are different
              # questions and, since the review, different storage.
              consecutive_probe_failures: instance.probe_failure_streak,
              instance_status: instance.status,
              paused: paused
            )
          rescue StandardError => e
            Rails.logger.error("[Internal::Devops::IntegrationHealth#probe] Failed for #{params[:id]}: #{e.message}")
            render_success(applied: false, error: e.message)
          end

          private

          # Scoped by the worker principal's own account COLUMN, so a nil
          # principal matches no rows instead of widening.
          def find_instance
            ::Devops::IntegrationInstance
              .where(account_id: worker_account_id)
              .find_by(id: params[:id])
          end

          def per_page
            @per_page ||= begin
              requested = params[:per_page].to_i
              requested.positive? ? [ requested, MAX_PER_PAGE ].min : DEFAULT_PER_PAGE
            end
          end
        end
      end
    end
  end
end
