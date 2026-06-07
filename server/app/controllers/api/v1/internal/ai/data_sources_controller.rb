# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        # Worker-only (mTLS) data-source monitor tick endpoints. The standalone
        # Sidekiq worker fires thin cron ticks here; all poll/fetch/change-detect/
        # signal logic runs server-side in Ai::DataSources::MonitorService.
        #
        # Lives under Internal::Ai (route namespace internal/ai/data_sources) like
        # the sibling internal AI callbacks (memory_pools, agent_executions, ...).
        # Inherits InternalBaseController mTLS auth (skip JWT,
        # authenticate_worker_via_mtls!) like every other /api/v1/internal endpoint.
        class DataSourcesController < InternalBaseController
          # POST /api/v1/internal/ai/data_sources/monitor_tick
          # Walk due subscriptions across all accounts and poll each.
          def monitor_tick
            limit = params[:limit].present? ? params[:limit].to_i.clamp(1, 1000) : 100
            result = ::Ai::DataSources::MonitorService.new.tick(limit: limit)
            render_success(result)
          rescue StandardError => e
            Rails.logger.error("[Internal::Ai::DataSourcesController] monitor_tick failed: #{e.class}: #{e.message}")
            render_error("Monitor tick failed: #{e.message}")
          end

          # POST /api/v1/internal/ai/data_sources/health_tick
          # Refresh the health status of every active source.
          def health_tick
            result = ::Ai::DataSources::MonitorService.new.health_tick
            render_success(result)
          rescue StandardError => e
            Rails.logger.error("[Internal::Ai::DataSourcesController] health_tick failed: #{e.class}: #{e.message}")
            render_error("Health tick failed: #{e.message}")
          end

          # POST /api/v1/internal/ai/data_sources/schema_sync_tick
          # Walk schema-tracked (or baseline-less) endpoints across all accounts,
          # sample each, and record an inferred schema version.
          def schema_sync_tick
            limit = params[:limit].present? ? params[:limit].to_i.clamp(1, 1000) : 100
            result = ::Ai::DataSources::SchemaSyncService.new.sync(limit: limit)
            render_success(result)
          rescue StandardError => e
            Rails.logger.error("[Internal::Ai::DataSourcesController] schema_sync_tick failed: #{e.class}: #{e.message}")
            render_error("Schema sync tick failed: #{e.message}")
          end
        end
      end
    end
  end
end
