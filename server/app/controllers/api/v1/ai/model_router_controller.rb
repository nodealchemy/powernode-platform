# frozen_string_literal: true

# Model Router Controller - Intelligent AI Request Routing
#
# Provides endpoints for managing routing rules, viewing routing decisions,
# cost optimization analysis, and provider selection strategies.
#
# Revenue Model: Usage-based + optimization savings share
# - Base tier: Fixed routing rules (included in subscription)
# - Pro tier: ML-optimized routing ($99-299/mo)
# - Enterprise: Custom models + savings share (10-15% of savings)
#
module Api
  module V1
    module Ai
      class ModelRouterController < ApplicationController
        include AuditLogging

        before_action :validate_permissions
        before_action :set_routing_rule, only: [ :show_rule, :update_rule, :destroy_rule, :toggle_rule ]
        before_action :set_time_range, only: [ :statistics, :cost_analysis, :decisions ]

        # ==========================================================================
        # ROUTING RULES MANAGEMENT
        # ==========================================================================

        # GET /api/v1/ai/model_router/rules
        def rules_index
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 20, 100 ].min

          rules = current_user.account.ai_model_routing_rules
                              .order(priority: :asc, created_at: :desc)

          # Apply filters
          rules = rules.active if params[:active] == "true"
          rules = rules.by_type(params[:rule_type]) if params[:rule_type].present?

          paginated_rules = rules.page(page).per(per_page)

          render_success({
            rules: paginated_rules.map(&:summary),
            pagination: pagination_data(paginated_rules)
          })
        end

        # GET /api/v1/ai/model_router/rules/:id
        def show_rule
          render_success({
            rule: {
              id: @routing_rule.id,
              name: @routing_rule.name,
              description: @routing_rule.description,
              rule_type: @routing_rule.rule_type,
              priority: @routing_rule.priority,
              is_active: @routing_rule.is_active,
              conditions: @routing_rule.conditions,
              target: @routing_rule.target,
              thresholds: {
                max_latency_ms: @routing_rule.max_latency_ms,
                min_quality_score: @routing_rule.min_quality_score,
                max_cost_per_1k_tokens: @routing_rule.max_cost_per_1k_tokens
              },
              stats: {
                times_matched: @routing_rule.times_matched,
                times_succeeded: @routing_rule.times_succeeded,
                times_failed: @routing_rule.times_failed,
                success_rate: @routing_rule.success_rate,
                last_matched_at: @routing_rule.last_matched_at
              },
              created_at: @routing_rule.created_at,
              updated_at: @routing_rule.updated_at
            }
          })
        end

        # POST /api/v1/ai/model_router/rules
        def create_rule
          rule = current_user.account.ai_model_routing_rules.build(routing_rule_params)

          if rule.save
            log_audit_event("ai.model_router.rule.create", rule)

            render_success({
              rule: rule.summary,
              message: "Routing rule created successfully"
            }, status: :created)
          else
            render_error("Failed to create routing rule: #{rule.errors.full_messages.join(', ')}", status: :unprocessable_content)
          end
        end

        # PATCH /api/v1/ai/model_router/rules/:id
        def update_rule
          if @routing_rule.update(routing_rule_params)
            log_audit_event("ai.model_router.rule.update", @routing_rule)

            render_success({
              rule: @routing_rule.summary,
              message: "Routing rule updated successfully"
            })
          else
            render_error("Failed to update routing rule: #{@routing_rule.errors.full_messages.join(', ')}", status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/model_router/rules/:id
        def destroy_rule
          @routing_rule.destroy

          log_audit_event("ai.model_router.rule.delete", @routing_rule)

          render_success({
            message: "Routing rule deleted successfully"
          })
        end

        # POST /api/v1/ai/model_router/rules/:id/toggle
        def toggle_rule
          @routing_rule.update!(is_active: !@routing_rule.is_active)

          log_audit_event("ai.model_router.rule.toggle", @routing_rule,
            metadata: { is_active: @routing_rule.is_active }
          )

          render_success({
            rule: @routing_rule.summary,
            message: "Routing rule #{@routing_rule.is_active ? 'activated' : 'deactivated'}"
          })
        end

        # ==========================================================================
        # ROUTING OPERATIONS
        # ==========================================================================

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

        # ==========================================================================
        # ROUTING DECISIONS
        # ==========================================================================

        # GET /api/v1/ai/model_router/decisions
        def decisions
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 50, 200 ].min

          decisions = ::Ai::RoutingDecision.for_account(current_user.account)
                                           .where("created_at >= ?", @time_range.ago)
                                           .order(created_at: :desc)

          # Apply filters
          decisions = decisions.by_strategy(params[:strategy]) if params[:strategy].present?
          decisions = decisions.where(outcome: params[:outcome]) if params[:outcome].present?
          decisions = decisions.for_provider(params[:provider_id]) if params[:provider_id].present?

          paginated = decisions.page(page).per(per_page)

          render_success({
            decisions: paginated.map(&:summary),
            pagination: pagination_data(paginated),
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/model_router/decisions/:id
        def show_decision
          decision = ::Ai::RoutingDecision.find(params[:id])

          unless decision.account_id == current_user.account_id
            return render_error("Decision not found", status: :not_found)
          end

          render_success({
            decision: {
              id: decision.id,
              request_type: decision.request_type,
              request_metadata: decision.request_metadata,
              strategy_used: decision.strategy_used,
              selected_provider: {
                id: decision.selected_provider_id,
                name: decision.selected_provider&.name
              },
              routing_rule: decision.routing_rule ? {
                id: decision.routing_rule_id,
                name: decision.routing_rule.name
              } : nil,
              candidates_evaluated: decision.evaluated_candidates,
              scoring_breakdown: decision.scoring_breakdown,
              decision_reason: decision.decision_reason,
              outcome: decision.outcome,
              cost: {
                estimated: decision.estimated_cost_usd,
                actual: decision.actual_cost_usd,
                alternative: decision.alternative_cost_usd,
                savings: decision.savings_usd
              },
              performance: {
                estimated_tokens: decision.estimated_tokens,
                actual_tokens: decision.actual_tokens_used,
                latency_ms: decision.actual_latency_ms,
                quality_score: decision.quality_score
              },
              created_at: decision.created_at
            }
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Decision not found", status: :not_found)
        end

        # ==========================================================================
        # STATISTICS & ANALYTICS
        # ==========================================================================

        # GET /api/v1/ai/model_router/statistics
        def statistics
          router_service = ::Ai::ModelRouterService.new(
            account: current_user.account,
            strategy: "cost_optimized"
          )

          stats = router_service.statistics(time_range: @time_range)

          render_success({
            statistics: stats,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/model_router/cost_analysis
        def cost_analysis
          router_service = ::Ai::ModelRouterService.new(
            account: current_user.account,
            strategy: "cost_optimized"
          )

          savings = router_service.analyze_cost_savings(time_range: @time_range)

          log_audit_event("ai.model_router.cost_analysis", current_user.account)

          render_success({
            cost_analysis: savings,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/model_router/provider_rankings
        def provider_rankings
          router_service = ::Ai::ModelRouterService.new(
            account: current_user.account,
            strategy: "cost_optimized"
          )

          rankings = router_service.provider_rankings

          render_success({
            rankings: rankings
          })
        end

        # GET /api/v1/ai/model_router/recommendations
        def recommendations
          router_service = ::Ai::ModelRouterService.new(
            account: current_user.account,
            strategy: "cost_optimized"
          )

          recommendations = router_service.get_optimization_recommendations

          render_success({
            recommendations: recommendations,
            generated_at: Time.current.iso8601
          })
        end

        # ==========================================================================
        # COST OPTIMIZATION LOGS
        # ==========================================================================

        # GET /api/v1/ai/model_router/optimizations
        def optimizations_index
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 20, 100 ].min

          logs = ::Ai::CostOptimizationLog.for_account(current_user.account)
                                          .order(created_at: :desc)

          # Apply filters
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

          # Create optimization logs for new opportunities
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

        # ==========================================================================
        # AUTHORIZATION
        # ==========================================================================

        def validate_permissions
          case action_name
          when "rules_index", "show_rule", "decisions", "show_decision", "statistics",
               "cost_analysis", "provider_rankings", "recommendations", "optimizations_index"
            require_permission("ai.routing.read")
          when "create_rule", "update_rule", "destroy_rule", "toggle_rule", "route"
            require_permission("ai.routing.manage")
          when "identify_optimizations", "apply_optimization"
            require_permission("ai.routing.optimize")
          end
        end

        # ==========================================================================
        # PARAMETER HANDLING
        # ==========================================================================

        def set_routing_rule
          @routing_rule = current_user.account.ai_model_routing_rules.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Routing rule not found", status: :not_found)
        end

        def set_time_range
          range_param = params[:time_range]

          @time_range = case range_param
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

        def routing_rule_params
          params.require(:rule).permit(
            :name,
            :description,
            :rule_type,
            :priority,
            :is_active,
            :max_latency_ms,
            :min_quality_score,
            :max_cost_per_1k_tokens,
            conditions: {},
            target: {}
          )
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
