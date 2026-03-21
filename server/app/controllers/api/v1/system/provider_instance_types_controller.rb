# frozen_string_literal: true

module Api
  module V1
    module System
      class ProviderInstanceTypesController < BaseController
        before_action :set_account
        before_action :set_provider, if: -> { params[:provider_id].present? }
        before_action :set_instance_type, only: [:show, :update, :destroy]

        def index
          authorize_permission!("system.providers.read")

          instance_types = if @provider
                             @provider.provider_instance_types
                           else
                             @account.system_provider_instance_types
                           end

          instance_types = apply_filters(instance_types)
          instance_types = paginate(instance_types)

          render_success(
            instance_types: serialize_collection(instance_types),
            meta: pagination_meta
          )
        end

        def show
          authorize_permission!("system.providers.read")
          render_success(instance_type: serialize_instance_type(@instance_type))
        end

        def create
          authorize_permission!("system.providers.create")

          provider = params[:provider_id].present? ? @provider : find_provider_from_params
          instance_type = provider.provider_instance_types.build(instance_type_params)
          instance_type.account = @account

          if instance_type.save
            render_success(instance_type: serialize_instance_type(instance_type), status: :created)
          else
            render_validation_error(instance_type)
          end
        end

        def update
          authorize_permission!("system.providers.update")

          if @instance_type.update(instance_type_params)
            render_success(instance_type: serialize_instance_type(@instance_type))
          else
            render_validation_error(@instance_type)
          end
        end

        def destroy
          authorize_permission!("system.providers.delete")

          if @instance_type.destroy
            render_success(message: "Instance type deleted successfully")
          else
            render_error("Failed to delete instance type", status: :unprocessable_entity)
          end
        end

        # Get instance types available in a specific region
        def for_region
          authorize_permission!("system.providers.read")

          region = @account.system_provider_regions.find(params[:region_id])
          instance_types = region.provider_instance_types.enabled

          render_success(
            instance_types: serialize_collection(instance_types)
          )
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider Region")
        end

        private

        def set_provider
          @provider = @account.system_providers.find(params[:provider_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider")
        end

        def set_instance_type
          @instance_type = if @provider
                             @provider.provider_instance_types.find(params[:id])
                           else
                             @account.system_provider_instance_types.find(params[:id])
                           end
        rescue ActiveRecord::RecordNotFound
          render_not_found("Instance Type")
        end

        def find_provider_from_params
          provider_id = params.dig(:instance_type, :provider_id)
          raise ActiveRecord::RecordNotFound unless provider_id

          @account.system_providers.find(provider_id)
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider")
        end

        def instance_type_params
          params.require(:instance_type).permit(
            :name, :description, :instance_type_code, :vcpus, :memory_mb,
            :storage_gb, :hourly_price, :enabled, :provider_id,
            specs: {}
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.by_vcpus(params[:min_vcpus].to_i) if params[:min_vcpus].present?
          scope = scope.by_memory(params[:min_memory].to_i) if params[:min_memory].present?
          scope
        end

        def serialize_instance_type(instance_type)
          ::System::ProviderInstanceTypeSerializer.new(instance_type).as_json
        end

        def serialize_collection(instance_types)
          instance_types.map { |it| serialize_instance_type(it) }
        end
      end
    end
  end
end
