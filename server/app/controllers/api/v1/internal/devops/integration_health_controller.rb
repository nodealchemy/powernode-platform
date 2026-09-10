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
          def index
            scope = ::Devops::IntegrationInstance
              .where(account_id: worker_account_id, status: "active")
              .order(:created_at)

            total = scope.count
            instances = scope.limit(per_page).offset((page - 1) * per_page)

            render_success({
              instances: instances.map { |i| { id: i.id, slug: i.slug } },
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total,
                total_pages: [ (total.to_f / per_page).ceil, 1 ].max
              }
            })
          end

          # POST /api/v1/internal/devops/integration_health/:id/probe
          def probe
            instance = find_instance

            # Deleted between listing and probe, or another account's row — the
            # two are deliberately indistinguishable in the response: saying
            # "exists, but not yours" would itself disclose the row.
            return render_success(applied: false, reason: "instance_not_found") unless instance

            unless instance.status == "active"
              return render_success(applied: false, reason: "not_active", status: instance.status)
            end

            result = ::Devops::ExecutionService.test_connection(instance: instance)
            paused = instance.record_health_probe!(
              success: result[:success],
              error: result[:message],
              metrics: { "last_probe_at" => Time.current.iso8601 }.compact
            )

            render_success(
              applied: true,
              health_status: instance.health_status,
              consecutive_failures: instance.consecutive_failures,
              status: instance.status,
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

          def page
            @page ||= [ params[:page].to_i, 1 ].max
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
