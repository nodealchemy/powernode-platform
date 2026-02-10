# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Docker
        class NetworksController < ApplicationController
          include AuditLogging

          before_action :set_host

          # GET /api/v1/devops/docker/hosts/:host_id/networks
          def index
            client = ::Devops::Docker::ApiClient.new(@host)

            begin
              networks = client.network_list
              render_success(items: networks)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch networks: #{e.message}", status: :unprocessable_content)
            end
          end

          # GET /api/v1/devops/docker/hosts/:host_id/networks/:id
          def show
            client = ::Devops::Docker::ApiClient.new(@host)

            begin
              network = client.network_inspect(params[:id])
              render_success(network: network)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Network not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch network: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/docker/hosts/:host_id/networks
          def create
            client = ::Devops::Docker::ApiClient.new(@host)

            begin
              result = client.network_create(network_params)
              render_success({ network: result }, status: :created)
              log_audit_event("docker.networks.create", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Network creation failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # DELETE /api/v1/devops/docker/hosts/:host_id/networks/:id
          def destroy
            client = ::Devops::Docker::ApiClient.new(@host)

            begin
              client.network_delete(params[:id])
              render_success(message: "Network removed successfully")
              log_audit_event("docker.networks.delete", @host)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Network not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Network removal failed: #{e.message}", status: :unprocessable_content)
            end
          end

          private

          def set_host
            @host = current_user.account.devops_docker_hosts.find(params[:host_id])
          end

          def network_params
            params.require(:network).permit(:name, :driver, :internal, :attachable, Labels: {}, Options: {}).to_h
          end
        end
      end
    end
  end
end
