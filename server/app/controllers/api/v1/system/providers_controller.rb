# frozen_string_literal: true

module Api
  module V1
    module System
      class ProvidersController < BaseController
        before_action :set_account
        before_action :set_provider, only: [:show, :update, :destroy, :test]

        def index
          authorize_permission!("system.providers.read")
          providers = @account.system_providers
          providers = apply_filters(providers)
          providers = paginate(providers)
          render_success(providers: serialize_collection(providers), meta: pagination_meta)
        end

        def show
          authorize_permission!("system.providers.read")
          render_success(provider: serialize_provider(@provider))
        end

        def create
          authorize_permission!("system.providers.create")
          provider = @account.system_providers.build(provider_params)

          if provider.save
            render_success(provider: serialize_provider(provider), status: :created)
          else
            render_validation_error(provider)
          end
        end

        def update
          authorize_permission!("system.providers.update")

          if @provider.update(provider_params)
            render_success(provider: serialize_provider(@provider))
          else
            render_validation_error(@provider)
          end
        end

        def destroy
          authorize_permission!("system.providers.delete")

          if @provider.destroy
            render_success(message: "Provider deleted successfully")
          else
            render_error("Failed to delete provider", status: :unprocessable_entity)
          end
        end

        def test
          authorize_permission!("system.providers.test")
          # Provider connection testing would be implemented here
          render_success(message: "Provider test not yet implemented", data: { provider_id: @provider.id })
        end

        private

        def set_provider
          @provider = @account.system_providers.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider")
        end

        def provider_params
          params.require(:provider).permit(
            :name, :description, :provider_type, :enabled, :public,
            config: {}, capabilities: {}
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.by_type(params[:provider_type]) if params[:provider_type].present?
          scope.ordered
        end

        def serialize_provider(provider)
          ::System::ProviderSerializer.new(provider).as_json
        end

        def serialize_collection(providers)
          providers.map { |p| serialize_provider(p) }
        end
      end
    end
  end
end
