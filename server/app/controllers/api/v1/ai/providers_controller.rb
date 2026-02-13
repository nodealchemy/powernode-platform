# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ProvidersController < ApplicationController
        include AuditLogging
        include ::Ai::ProviderSerialization

        before_action :set_provider, only: [
          :show, :update, :destroy,
          :models, :usage_summary, :check_availability
        ]
        before_action :validate_permissions

        # GET /api/v1/ai/providers
        def index
          providers = current_user.account.ai_providers
                                 .includes(:provider_credentials)

          providers = providers.active unless current_user.has_permission?("admin.ai.providers.read")

          providers = apply_provider_filters(providers)
          providers = apply_sorting(providers)
          providers = apply_pagination(providers)

          render_success({
            items: providers.map { |p| serialize_provider(p) },
            pagination: pagination_data(providers)
          })

          log_audit_event("ai.providers.read", current_user.account)
        end

        # GET /api/v1/ai/providers/:id
        def show
          render_success({
            provider: serialize_provider_detail(@provider)
          })

          log_audit_event("ai.providers.read", @provider)
        end

        # POST /api/v1/ai/providers
        def create
          @provider = ::Ai::Provider.new(provider_params)
          @provider.account = current_user.account

          if @provider.save
            render_success({
              provider: serialize_provider_detail(@provider)
            }, status: :created)

            log_audit_event("ai.providers.create", @provider,
              provider_type: @provider.provider_type
            )
          else
            render_validation_error(@provider.errors)
          end
        end

        # PATCH /api/v1/ai/providers/:id
        def update
          if @provider.update(provider_params)
            render_success({
              provider: serialize_provider_detail(@provider)
            })

            log_audit_event("ai.providers.update", @provider,
              changes: @provider.previous_changes.keys
            )
          else
            render_validation_error(@provider.errors)
          end
        end

        # DELETE /api/v1/ai/providers/:id
        def destroy
          provider_name = @provider.name

          if @provider.destroy
            render_success({ message: "AI provider deleted successfully" })

            log_audit_event("ai.providers.delete", current_user.account,
              provider_name: provider_name
            )
          else
            if @provider.errors.any?
              render_validation_error(@provider.errors)
            else
              render_error("Failed to delete provider", status: :unprocessable_content)
            end
          end
        end

        # GET /api/v1/ai/providers/:id/models
        def models
          render_success({
            provider: {
              id: @provider.id,
              name: @provider.name,
              provider_type: @provider.provider_type
            },
            models: @provider.supported_models || [],
            count: @provider.supported_models&.length || 0
          })
        end

        # GET /api/v1/ai/providers/:id/usage_summary
        def usage_summary
          period_days = params[:period]&.to_i || 30
          period = period_days.days

          summary = ::Ai::ProviderManagementService.provider_usage_summary(
            @provider,
            current_user.account,
            period
          )

          render_success({
            provider: serialize_provider(@provider),
            usage_summary: summary,
            period: {
              days: period_days,
              start_date: period_days.days.ago.to_date,
              end_date: Date.current
            }
          })
        end

        # GET /api/v1/ai/providers/available
        def available
          providers = ::Ai::ProviderManagementService.get_available_providers_for_account(current_user.account)

          render_success({
            providers: providers.map { |p| serialize_provider(p) },
            count: providers.count
          })
        end

        # GET /api/v1/ai/providers/statistics
        def statistics
          providers = current_user.account.ai_providers

          stats = {
            total_providers: providers.count,
            active_providers: providers.where(is_active: true).count,
            providers_by_type: providers.group(:provider_type).count,
            total_credentials: ::Ai::ProviderCredential.joins(:provider)
                                                  .where(ai_providers: { account_id: current_user.account_id })
                                                  .count,
            total_api_calls: calculate_total_api_calls,
            total_cost: calculate_total_cost
          }

          render_success({ statistics: stats })
        end

        # GET /api/v1/ai/providers/:id/check_availability
        def check_availability
          availability_result = ProviderAvailabilityService.check_provider(@provider)

          render_success({
            provider: {
              id: @provider.id,
              name: @provider.name,
              provider_type: @provider.provider_type
            },
            availability: {
              available: availability_result[:available],
              reason: availability_result[:reason],
              is_active: @provider.is_active?,
              is_healthy: @provider.healthy?,
              has_credentials: @provider.provider_credentials.where(is_active: true).exists?,
              has_models: @provider.available_models.any?,
              health_status: @provider.health_status
            }
          })
        end

        private

        def set_provider
          @provider = current_user.account.ai_providers.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "index", "show", "available", "statistics", "models", "usage_summary", "check_availability"
            require_permission("ai.providers.read")
          when "create"
            require_permission("ai.providers.create")
          when "update"
            require_permission("ai.providers.update")
          when "destroy"
            require_permission("ai.providers.delete")
          end
        end

        def provider_params
          params.require(:provider).permit(
            :name, :provider_type, :api_base_url, :is_active,
            :priority_order, :description, :api_endpoint, :documentation_url,
            :status_url, :requires_auth, :supports_streaming, :supports_functions,
            :supports_vision, :supports_code_execution, :slug,
            capabilities: [],
            supported_models: [ :name, :id, :context_length, :max_output_tokens, :cost_per_token,
                              { cost_per_1k_tokens: [ :input, :output ] }, :capabilities, :features,
                              :default_parameters ],
            default_parameters: {},
            rate_limits: {},
            pricing_info: {},
            configuration_schema: {},
            metadata: {}
          )
        end

        def apply_provider_filters(providers)
          providers = providers.where(provider_type: params[:provider_type]) if params[:provider_type].present?
          providers = providers.supporting_capability(params[:capability]) if params[:capability].present?
          providers = providers.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%") if params[:search].present?
          providers
        end

        def apply_sorting(collection)
          sort = params[:sort] || "priority"

          case sort
          when "name"
            collection.order(:name)
          when "priority"
            collection.order(:priority_order, :name)
          when "created_at"
            collection.order(created_at: :desc)
          else
            collection.ordered_by_priority rescue collection.order(:name)
          end
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 20, 100 ].min

          collection.page(page).per(per_page)
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        def calculate_total_api_calls
          agent_calls = ::Ai::AgentExecution.joins(agent: :provider)
                                       .where(ai_providers: { account_id: current_user.account_id })
                                       .count

          workflow_calls = ::Ai::WorkflowNodeExecution.joins(workflow_run: { workflow: :account })
                                                  .where(accounts: { id: current_user.account_id })
                                                  .where(node_type: "ai_agent")
                                                  .count

          agent_calls + workflow_calls
        end

        def calculate_total_cost
          agent_cost = ::Ai::AgentExecution.joins(agent: :provider)
                                      .where(ai_providers: { account_id: current_user.account_id })
                                      .sum(:cost_usd)

          workflow_cost = ::Ai::WorkflowNodeExecution.joins(workflow_run: { workflow: :account })
                                                 .where(accounts: { id: current_user.account_id })
                                                 .sum(:cost)

          (agent_cost + workflow_cost).round(2)
        end
      end
    end
  end
end
