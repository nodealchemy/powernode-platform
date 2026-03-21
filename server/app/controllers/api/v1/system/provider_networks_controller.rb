# frozen_string_literal: true

module Api
  module V1
    module System
      class ProviderNetworksController < BaseController
        before_action :set_network, only: [:show, :update, :destroy]

        # GET /api/v1/system/provider_networks
        def index
          authorize_permission!('system.networks.read')

          networks = current_account.system_provider_networks
          networks = apply_filters(networks)
          networks = paginate(networks.includes(:provider, :provider_region, :subnets).by_name)

          render_success(
            networks: networks.map { |n| ::System::ProviderNetworkSerializer.new(n).as_json },
            meta: pagination_meta
          )
        end

        # GET /api/v1/system/provider_networks/:id
        def show
          authorize_permission!('system.networks.read')
          render_success(network: ::System::ProviderNetworkSerializer.new(@network).as_json)
        end

        # POST /api/v1/system/provider_networks
        def create
          authorize_permission!('system.networks.create')

          network = current_account.system_provider_networks.build(network_params)

          if network.save
            render_success(network: ::System::ProviderNetworkSerializer.new(network).as_json, status: :created)
          else
            render_validation_error(network)
          end
        end

        # PATCH/PUT /api/v1/system/provider_networks/:id
        def update
          authorize_permission!('system.networks.update')

          if @network.update(network_params)
            render_success(network: ::System::ProviderNetworkSerializer.new(@network).as_json)
          else
            render_validation_error(@network)
          end
        end

        # DELETE /api/v1/system/provider_networks/:id
        def destroy
          authorize_permission!('system.networks.delete')

          unless @network.can_delete?
            return render_error('Cannot delete network (may be default or has subnets)', status: :unprocessable_entity)
          end

          @network.update!(status: 'deleting')
          render_success(message: 'Network deletion initiated')
        end

        private

        def set_network
          @network = current_account.system_provider_networks.find(params[:id])
        end

        def network_params
          params.require(:network).permit(
            :name, :description, :cidr_block, :is_default,
            :enable_dns_support, :enable_dns_hostnames,
            :provider_id, :provider_region_id, config: {}
          )
        end

        def apply_filters(networks)
          networks = networks.by_status(params[:status]) if params[:status].present?
          networks = networks.default_networks if params[:default] == 'true'
          networks = networks.custom_networks if params[:default] == 'false'
          networks = networks.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
          networks
        end
      end
    end
  end
end
