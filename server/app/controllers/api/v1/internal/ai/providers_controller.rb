# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class ProvidersController < InternalBaseController
          def index
            providers = ::Ai::Provider.all
            providers = providers.where(is_active: true) unless params[:include_disabled] == "true"

            render_success(providers: providers.map { |p|
              { id: p.id, name: p.name, provider_type: p.provider_type,
                api_base_url: p.api_base_url, enabled: p.is_active }
            })
          end

          # POST /api/v1/internal/ai/provider_health_metrics
          # Called by AiProviderHealthCheckJob to persist health check results
          def store_health_metrics
            providers_data = params[:providers] || {}
            updated = 0

            providers_data.each do |_name, health_data|
              provider = ::Ai::Provider.find_by(id: health_data[:id])
              next unless provider

              success = health_data[:status] == "healthy"
              response_time = health_data[:response_time_ms]
              error_msg = health_data[:issues]&.first

              provider.update_health_metrics(success, response_time, error_msg)
              updated += 1
            end

            render_success(updated_count: updated)
          rescue StandardError => e
            render_internal_error("Failed to store health metrics", exception: e)
          end

          # POST /api/v1/internal/ai/providers/sync_all
          # Called by AiProviderModelSyncJob to refresh model lists from upstream APIs
          def sync_all
            force_refresh = params[:force_refresh] == true || params[:force_refresh] == "true"
            results = ::Ai::ProviderManagementService.sync_all_providers(force_refresh: force_refresh)

            render_success(results: results)
          rescue StandardError => e
            render_internal_error("Failed to sync providers", exception: e)
          end
        end
      end
    end
  end
end
