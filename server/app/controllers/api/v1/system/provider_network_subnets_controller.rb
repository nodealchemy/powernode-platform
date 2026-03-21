# frozen_string_literal: true

module Api
  module V1
    module System
      class ProviderNetworkSubnetsController < BaseController
        before_action :set_account
        before_action :set_network
        before_action :set_subnet, only: [:show, :update, :destroy]

        def index
          authorize_permission!("system.networks.read")

          subnets = @network.provider_network_subnets
          subnets = apply_filters(subnets)
          subnets = paginate(subnets)

          render_success(
            subnets: serialize_collection(subnets),
            meta: pagination_meta
          )
        end

        def show
          authorize_permission!("system.networks.read")
          render_success(subnet: serialize_subnet(@subnet))
        end

        def create
          authorize_permission!("system.networks.create")

          subnet = @network.provider_network_subnets.build(subnet_params)

          if subnet.save
            render_success(subnet: serialize_subnet(subnet), status: :created)
          else
            render_validation_error(subnet)
          end
        end

        def update
          authorize_permission!("system.networks.update")

          if @subnet.update(subnet_params)
            render_success(subnet: serialize_subnet(@subnet))
          else
            render_validation_error(@subnet)
          end
        end

        def destroy
          authorize_permission!("system.networks.delete")

          if @subnet.destroy
            render_success(message: "Subnet deleted successfully")
          else
            render_error("Failed to delete subnet", status: :unprocessable_entity)
          end
        end

        private

        def set_network
          @network = @account.system_provider_networks.find(params[:network_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Provider Network")
        end

        def set_subnet
          @subnet = @network.provider_network_subnets.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Subnet")
        end

        def subnet_params
          params.require(:subnet).permit(
            :name, :description, :cidr_block, :status, :is_public, :enabled,
            :provider_availability_zone_id,
            config: {}
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.where(is_public: true) if params[:public] == "true"
          scope = scope.where(is_public: false) if params[:public] == "false"
          if params[:availability_zone_id].present?
            scope = scope.where(provider_availability_zone_id: params[:availability_zone_id])
          end
          scope
        end

        def serialize_subnet(subnet)
          ::System::ProviderNetworkSubnetSerializer.new(subnet).as_json
        end

        def serialize_collection(subnets)
          subnets.map { |s| serialize_subnet(s) }
        end
      end
    end
  end
end
