# frozen_string_literal: true

module Api
  module BaaS
    module V1
      class TenantsController < Api::BaaS::BaseController
        skip_before_action :authenticate_baas_request!, only: [ :create ]
        before_action :authenticate_internal!, only: [ :create ]

        # GET /api/baas/v1/tenant
        def show
          render_success(data: current_tenant.summary)
        end

        # POST /api/baas/v1/tenant (internal use - create tenant)
        def create
          service = ::BaaS::TenantService.new(account: @current_account)
          result = service.create_tenant(tenant_params)

          if result[:success]
            render_success(data: result[:tenant].summary, status: :created)
          else
            render_error(result[:errors]&.join(", ") || result[:error])
          end
        end

        # PATCH /api/baas/v1/tenant
        def update
          service = ::BaaS::TenantService.new(tenant: current_tenant)
          result = service.update_tenant(tenant_params)

          if result[:success]
            render_success(data: result[:tenant].summary)
          else
            render_error(result[:errors]&.join(", ") || result[:error])
          end
        end

        # GET /api/baas/v1/tenant/dashboard
        def dashboard
          service = ::BaaS::TenantService.new(tenant: current_tenant)
          result = service.dashboard_stats

          if result[:success]
            render_success(data: result[:stats])
          else
            render_error(result[:error])
          end
        end

        # GET /api/baas/v1/tenant/limits
        def limits
          service = ::BaaS::TenantService.new(tenant: current_tenant)
          render_success(data: service.check_rate_limits)
        end

        # GET /api/baas/v1/tenant/billing_configuration
        def billing_configuration
          config = current_tenant.billing_configuration
          render_success(data: config&.settings_summary)
        end

        # PATCH /api/baas/v1/tenant/billing_configuration
        def update_billing_configuration
          config = current_tenant.billing_configuration

          allowed = params.permit(
            :invoice_prefix, :invoice_due_days, :auto_invoice, :auto_charge,
            :tax_enabled, :tax_provider, :default_tax_rate_id,
            :dunning_enabled, :dunning_attempts, :dunning_interval_days,
            :usage_billing_enabled, :metered_billing_enabled,
            :trial_enabled, :default_trial_days, settings: {}
          )

          if config.update(allowed)
            render_success(data: config.settings_summary)
          else
            render_error(config.errors.full_messages.join(", "))
          end
        end

        private

        def authenticate_internal!
          # This would be called from internal admin endpoints
          # For now, use standard account authentication
          token = request.headers["X-Internal-Token"]
          unless token.present? && valid_internal_token?(token)
            render_error("Unauthorized", status: :unauthorized)
          end
        end

        def valid_internal_token?(token)
          # In production, validate against a secure internal token
          # For now, allow if the request comes from the main API
          @current_account = Account.find_by(id: params[:account_id])
          @current_account.present?
        end

        def tenant_params
          params.permit(
            :name, :slug, :tier, :environment, :webhook_url, :webhook_secret,
            :default_currency, :timezone, branding: {}, metadata: {}
          )
        end
      end
    end
  end
end
