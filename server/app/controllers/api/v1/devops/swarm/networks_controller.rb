# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class NetworksController < ApplicationController
          include AuditLogging

          before_action :set_cluster

          # GET /api/v1/devops/swarm/clusters/:cluster_id/networks
          def index
            manager = ::Devops::Docker::NetworkManager.new(cluster: @cluster)

            begin
              networks = manager.list
              render_success(items: networks)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to list networks: #{e.message}", status: :unprocessable_entity)
            end
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/networks/:id
          def show
            manager = ::Devops::Docker::NetworkManager.new(cluster: @cluster)

            begin
              network = manager.inspect_network(params[:id])
              render_success(network: network)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Network not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to inspect network: #{e.message}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/networks
          def create
            manager = ::Devops::Docker::NetworkManager.new(cluster: @cluster)

            begin
              network = manager.create(network_params)
              render_success({ network: network }, status: :created)
              log_audit_event("swarm.networks.create", @cluster)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to create network: #{e.message}", status: :unprocessable_entity)
            end
          end

          # DELETE /api/v1/devops/swarm/clusters/:cluster_id/networks/:id
          def destroy
            manager = ::Devops::Docker::NetworkManager.new(cluster: @cluster)

            begin
              manager.remove(params[:id])
              render_success(message: "Network removed successfully")
              log_audit_event("swarm.networks.delete", @cluster)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Network not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to remove network: #{e.message}", status: :unprocessable_entity)
            end
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:cluster_id])
          end

          def network_params
            params.require(:network).permit(:name, :driver, :internal, :attachable, :ingress, labels: {}, options: {})
          end
        end
      end
    end
  end
end
