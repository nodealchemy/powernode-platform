# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ModelRouterController < ApplicationController
        include AuditLogging

        before_action :validate_permissions
        before_action :set_routing_rule, only: [ :show_rule, :update_rule, :destroy_rule, :toggle_rule ]
        before_action :set_time_range, only: [ :decisions ]

        # GET /api/v1/ai/model_router/rules
        def rules_index
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 20, 100 ].min

          rules = current_user.account.ai_model_routing_rules
                              .order(priority: :asc, created_at: :desc)

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
            render_success({ rule: rule.summary, message: "Routing rule created successfully" }, status: :created)
          else
            render_error("Failed to create routing rule: #{rule.errors.full_messages.join(', ')}", status: :unprocessable_content)
          end
        end

        # PATCH /api/v1/ai/model_router/rules/:id
        def update_rule
          if @routing_rule.update(routing_rule_params)
            log_audit_event("ai.model_router.rule.update", @routing_rule)
            render_success({ rule: @routing_rule.summary, message: "Routing rule updated successfully" })
          else
            render_error("Failed to update routing rule: #{@routing_rule.errors.full_messages.join(', ')}", status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/model_router/rules/:id
        def destroy_rule
          @routing_rule.destroy
          log_audit_event("ai.model_router.rule.delete", @routing_rule)
          render_success({ message: "Routing rule deleted successfully" })
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

        # GET /api/v1/ai/model_router/decisions
        def decisions
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 50, 200 ].min

          decisions = ::Ai::RoutingDecision.for_account(current_user.account)
                                           .where("created_at >= ?", @time_range.ago)
                                           .order(created_at: :desc)

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

        private

        def validate_permissions
          case action_name
          when "rules_index", "show_rule", "decisions", "show_decision"
            require_permission("ai.routing.read")
          when "create_rule", "update_rule", "destroy_rule", "toggle_rule"
            require_permission("ai.routing.manage")
          end
        end

        def set_routing_rule
          @routing_rule = current_user.account.ai_model_routing_rules.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Routing rule not found", status: :not_found)
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

        def routing_rule_params
          params.require(:rule).permit(
            :name, :description, :rule_type, :priority, :is_active,
            :max_latency_ms, :min_quality_score, :max_cost_per_1k_tokens,
            conditions: {}, target: {}
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
