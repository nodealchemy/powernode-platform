# frozen_string_literal: true

module Api
  module V1
    module System
      class ProviderRegionsController < BaseController
        before_action :set_account
        before_action :set_provider
        before_action :set_region, only: [:show, :update, :destroy]

        def index
          authorize_permission!("system.regions.read")
          regions = @provider.provider_regions
          regions = apply_filters(regions)
          regions = paginate(regions)
          render_success(regions: serialize_collection(regions), meta: pagination_meta)
        end

        def show
          authorize_permission!("system.regions.read")
          render_success(region: serialize_region(@region))
        end

        def create
          authorize_permission!("system.regions.create")
          region = @provider.provider_regions.build(region_params)
          region.account = @account

          if region.save
            render_success(region: serialize_region(region), status: :created)
          else
            render_validation_error(region)
          end
        end

        def update
          authorize_permission!("system.regions.update")

          if @region.update(region_params)
            render_success(region: serialize_region(@region))
          else
            render_validation_error(@region)
          end
        end

        def destroy
          authorize_permission!("system.regions.delete")

          if @region.destroy
            render_success(message: "Region deleted successfully")
          else
            render_error("Failed to delete region", status: :unprocessable_entity)
          end
        end

        private

        def set_provider
          @provider = @account.system_providers.find(params[:provider_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider")
        end

        def set_region
          @region = @provider.provider_regions.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider Region")
        end

        def region_params
          params.require(:provider_region).permit(
            :name, :description, :region_code, :endpoint_url, :enabled,
            :kernel_image, :machine_image, :ramdisk_image,
            capabilities: {}
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope.ordered
        end

        def serialize_region(region)
          ::System::ProviderRegionSerializer.new(region).as_json
        end

        def serialize_collection(regions)
          regions.map { |r| serialize_region(r) }
        end
      end
    end
  end
end
