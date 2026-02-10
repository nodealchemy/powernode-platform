# frozen_string_literal: true

module Api
  module V1
    module BaaS
      class ApiKeysController < Api::V1::BaaS::BaseController
        before_action :require_api_keys_scope, except: [ :index ]

        # GET /api/v1/baas/api_keys
        def index
          service = ::BaaS::ApiKeyService.new(tenant: current_tenant)
          result = service.list_keys(
            environment: params[:environment],
            key_type: params[:key_type],
            status: params[:status]
          )

          if result[:success]
            render_success(result[:api_keys])
          else
            render_error(result[:error])
          end
        end

        # GET /api/v1/baas/api_keys/:id
        def show
          service = ::BaaS::ApiKeyService.new(tenant: current_tenant)
          result = service.get_key(params[:id])

          if result[:success]
            render_success(result[:api_key])
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # POST /api/v1/baas/api_keys
        def create
          service = ::BaaS::ApiKeyService.new(tenant: current_tenant)
          result = service.create_key(api_key_params)

          if result[:success]
            # Include raw_key only on creation - it cannot be retrieved later
            render_success(
              result[:api_key].summary.merge(raw_key: result[:raw_key]),
              message: "API key created. Store this key securely - it cannot be retrieved later.",
              status: :created
            )
          else
            render_error(result[:errors]&.join(", ") || result[:error])
          end
        end

        # PATCH /api/v1/baas/api_keys/:id
        def update
          service = ::BaaS::ApiKeyService.new(tenant: current_tenant)
          result = service.update_key(params[:id], api_key_params)

          if result[:success]
            render_success(result[:api_key])
          else
            render_error(result[:errors]&.join(", ") || result[:error])
          end
        end

        # DELETE /api/v1/baas/api_keys/:id
        def destroy
          service = ::BaaS::ApiKeyService.new(tenant: current_tenant)
          result = service.revoke_key(params[:id])

          if result[:success]
            render_success(message: "API key revoked")
          else
            render_error(result[:error])
          end
        end

        # POST /api/v1/baas/api_keys/:id/roll
        def roll
          service = ::BaaS::ApiKeyService.new(tenant: current_tenant)
          result = service.roll_key(params[:id])

          if result[:success]
            render_success(
              result[:api_key].summary.merge(raw_key: result[:raw_key]),
              message: "API key rolled. Old key has been revoked."
            )
          else
            render_error(result[:error])
          end
        end

        private

        def require_api_keys_scope
          require_scope("api_keys")
        end

        def api_key_params
          params.permit(
            :name, :key_type, :environment, :rate_limit_per_minute,
            :rate_limit_per_day, :expires_at, scopes: [], metadata: {}
          )
        end
      end
    end
  end
end
