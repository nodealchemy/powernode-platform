# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class ConfigsController < ApplicationController
          include AuditLogging

          before_action :set_cluster

          # GET /api/v1/devops/swarm/clusters/:cluster_id/configs
          def index
            manager = ::Devops::Docker::SecretManager.new(cluster: @cluster)

            begin
              configs = manager.list_configs
              render_success(items: configs)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to list configs: #{e.message}", status: :unprocessable_content)
            end
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/configs/:id
          def show
            manager = ::Devops::Docker::SecretManager.new(cluster: @cluster)

            begin
              config = manager.inspect_config(params[:id])
              render_success(config: config)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Config not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to inspect config: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/configs
          def create
            manager = ::Devops::Docker::SecretManager.new(cluster: @cluster)

            begin
              config = manager.create_config(config_params)
              render_success({ config: config }, status: :created)
              log_audit_event("swarm.configs.create", @cluster)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to create config: #{e.message}", status: :unprocessable_content)
            end
          end

          # DELETE /api/v1/devops/swarm/clusters/:cluster_id/configs/:id
          def destroy
            manager = ::Devops::Docker::SecretManager.new(cluster: @cluster)

            begin
              manager.remove_config(params[:id])
              render_success(message: "Config removed successfully")
              log_audit_event("swarm.configs.delete", @cluster)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Config not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to remove config: #{e.message}", status: :unprocessable_content)
            end
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:cluster_id])
          end

          def config_params
            params.require(:config).permit(:name, :data, labels: {})
          end
        end
      end
    end
  end
end
