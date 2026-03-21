# frozen_string_literal: true

module Api
  module V1
    module System
      class ProviderAvailabilityZonesController < BaseController
        before_action :set_account
        before_action :set_provider
        before_action :set_region
        before_action :set_zone, only: [:show, :update, :destroy]

        def index
          authorize_permission!("system.regions.read")

          zones = @region.provider_availability_zones
          zones = apply_filters(zones)
          zones = paginate(zones)

          render_success(
            availability_zones: serialize_collection(zones),
            meta: pagination_meta
          )
        end

        def show
          authorize_permission!("system.regions.read")
          render_success(availability_zone: serialize_zone(@zone))
        end

        def create
          authorize_permission!("system.regions.create")

          zone = @region.provider_availability_zones.build(zone_params)

          if zone.save
            render_success(availability_zone: serialize_zone(zone), status: :created)
          else
            render_validation_error(zone)
          end
        end

        def update
          authorize_permission!("system.regions.update")

          if @zone.update(zone_params)
            render_success(availability_zone: serialize_zone(@zone))
          else
            render_validation_error(@zone)
          end
        end

        def destroy
          authorize_permission!("system.regions.delete")

          if @zone.destroy
            render_success(message: "Availability zone deleted successfully")
          else
            render_error("Failed to delete availability zone", status: :unprocessable_entity)
          end
        end

        private

        def set_provider
          @provider = @account.system_providers.find(params[:provider_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider")
        end

        def set_region
          @region = @provider.provider_regions.find(params[:region_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider Region")
        end

        def set_zone
          @zone = @region.provider_availability_zones.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Availability Zone")
        end

        def zone_params
          params.require(:availability_zone).permit(
            :name, :zone_code, :status, :enabled,
            capabilities: {}
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.available if params[:status] == "available"
          scope = scope.operational if params[:operational] == "true"
          scope
        end

        def serialize_zone(zone)
          ::System::ProviderAvailabilityZoneSerializer.new(zone).as_json
        end

        def serialize_collection(zones)
          zones.map { |z| serialize_zone(z) }
        end
      end
    end
  end
end
