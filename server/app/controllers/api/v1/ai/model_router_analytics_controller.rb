# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ModelRouterAnalyticsController < ApplicationController
        include AuditLogging

        before_action :validate_permissions
        before_action :set_time_range, only: [ :statistics, :cost_analysis ]

        # POST /api/v1/ai/model_router/route
        def route
          router_service = ::Ai::ModelRouterService.new(
            account: current_user.account,
            strategy: params[:strategy] || "cost_optimized"
          )

          request_context = {
            request_type: params[:request_type] || "completion",
            capabilities: Array(params[:capabilities]),
            estimated_tokens: params[:estimated_tokens]&.to_i,
            model_name: params[:model_name]
          }

          routing_result = router_service.route(request_context)

          render_success({
            routing: {
              provider_id: routing_result[:provider].id,
              provider_name: routing_result[:provider].name,
              decision_id: routing_result[:decision_id],
              strategy_used: routing_result[:strategy_used],
              estimated_cost_usd: routing_result[:estimated_cost],
              estimated_latency_ms: routing_result[:estimated_latency_ms],
              scoring: routing_result[:scoring]
            }
          })
        rescue ::Ai::ModelRouterService::NoProvidersAvailableError => e
          render_error(e.message, status: :service_unavailable)
        rescue StandardError => e
          render_internal_error("Routing failed", exception: e)
        end

        # GET /api/v1/ai/model_router/statistics
        def statistics
          router_service = ::Ai::ModelRouterService.new(
            account: current_user.account, strategy: "cost_optimized"
          )

          render_success({
            statistics: router_service.statistics(time_range: @time_range),
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/model_router/cost_analysis
        def cost_analysis
          router_service = ::Ai::ModelRouterService.new(
            account: current_user.account, strategy: "cost_optimized"
          )

          log_audit_event("ai.model_router.cost_analysis", current_user.account)

          render_success({
            cost_analysis: router_service.analyze_cost_savings(time_range: @time_range),
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/model_router/provider_rankings
        def provider_rankings
          router_service = ::Ai::ModelRouterService.new(
            account: current_user.account, strategy: "cost_optimized"
          )

          render_success({ rankings: router_service.provider_rankings })
        end

        # GET /api/v1/ai/model_router/recommendations
        def recommendations
          router_service = ::Ai::ModelRouterService.new(
            account: current_user.account, strategy: "cost_optimized"
          )

          render_success({
            recommendations: router_service.get_optimization_recommendations,
            generated_at: Time.current.iso8601
          })
        end

        # GET /api/v1/ai/model_router/optimizations
        def optimizations_index
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 20, 100 ].min

          logs = ::Ai::CostOptimizationLog.for_account(current_user.account)
                                          .order(created_at: :desc)

          logs = logs.by_type(params[:type]) if params[:type].present?
          logs = logs.where(status: params[:status]) if params[:status].present?
          logs = logs.high_impact if params[:high_impact] == "true"

          paginated = logs.page(page).per(per_page)

          render_success({
            optimizations: paginated.map(&:summary),
            pagination: pagination_data(paginated),
            stats: ::Ai::CostOptimizationLog.stats_for_account(current_user.account)
          })
        end

        # POST /api/v1/ai/model_router/optimizations/identify
        def identify_optimizations
          opportunities = ::Ai::CostOptimizationLog.identify_opportunities_for(current_user.account)

          created_count = 0
          opportunities.each do |opp|
            existing = ::Ai::CostOptimizationLog.for_account(current_user.account)
                                                 .for_resource(opp[:resource_type], opp[:resource_id])
                                                 .pending
                                                 .exists?
            next if existing

            ::Ai::CostOptimizationLog.create!(
              account: current_user.account,
              **opp.slice(:optimization_type, :resource_type, :resource_id, :description,
                          :current_cost_usd, :potential_savings_usd, :recommendation)
            )
            created_count += 1
          end

          log_audit_event("ai.model_router.optimizations.identify", current_user.account,
            metadata: { opportunities_found: opportunities.count, created: created_count }
          )

          render_success({
            opportunities_found: opportunities.count,
            new_optimizations_created: created_count,
            message: "Optimization analysis complete"
          })
        end

        # POST /api/v1/ai/model_router/optimizations/:id/apply
        def apply_optimization
          optimization = ::Ai::CostOptimizationLog.find(params[:id])

          unless optimization.account_id == current_user.account_id
            return render_error("Optimization not found", status: :not_found)
          end

          unless optimization.status.in?(%w[identified recommended])
            return render_error("Optimization cannot be applied in current status", status: :unprocessable_content)
          end

          optimization.apply!

          log_audit_event("ai.model_router.optimization.apply", optimization)

          render_success({
            optimization: optimization.summary,
            message: "Optimization applied successfully"
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Optimization not found", status: :not_found)
        end

        private

        def validate_permissions
          case action_name
          when "statistics", "cost_analysis", "provider_rankings", "recommendations", "optimizations_index"
            require_permission("ai.routing.read")
          when "route"
            require_permission("ai.routing.manage")
          when "identify_optimizations", "apply_optimization"
            require_permission("ai.routing.optimize")
          end
        end

        def set_time_range
          @time_range = case params[:time_range]
          when "1h" then 1.hour
          when "6h" then 6.hours
          when "24h", "1d" then 1.day
          when "7d", "1w" then 7.days
          when "30d", "1m" then 30.days
          when "90d", "3m" then 90.days
          else 24.hours
          end
        end

        def time_range_info
          {
            start: @time_range.ago.iso8601,
            end: Time.current.iso8601,
            period: params[:time_range] || "24h",
            seconds: @time_range.to_i
          }
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end
      end
    end
  end
end
