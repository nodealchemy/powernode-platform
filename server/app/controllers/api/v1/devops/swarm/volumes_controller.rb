# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class VolumesController < ApplicationController
          include AuditLogging

          before_action :set_cluster

          # GET /api/v1/devops/swarm/clusters/:cluster_id/volumes
          def index
            manager = ::Devops::Docker::VolumeManager.new(cluster: @cluster)

            begin
              volumes = manager.list
              render_success(items: volumes)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to list volumes: #{e.message}", status: :unprocessable_entity)
            end
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/volumes/:id
          def show
            manager = ::Devops::Docker::VolumeManager.new(cluster: @cluster)

            begin
              volume = manager.inspect_volume(params[:id])
              render_success(volume: volume)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Volume not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to inspect volume: #{e.message}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/volumes
          def create
            manager = ::Devops::Docker::VolumeManager.new(cluster: @cluster)

            begin
              volume = manager.create(volume_params)
              render_success({ volume: volume }, status: :created)
              log_audit_event("swarm.volumes.create", @cluster)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to create volume: #{e.message}", status: :unprocessable_entity)
            end
          end

          # DELETE /api/v1/devops/swarm/clusters/:cluster_id/volumes/:id
          def destroy
            manager = ::Devops::Docker::VolumeManager.new(cluster: @cluster)

            begin
              manager.remove(params[:id])
              render_success(message: "Volume removed successfully")
              log_audit_event("swarm.volumes.delete", @cluster)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Volume not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to remove volume: #{e.message}", status: :unprocessable_entity)
            end
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:cluster_id])
          end

          def volume_params
            params.require(:volume).permit(:name, :driver, labels: {}, driver_opts: {})
          end
        end
      end
    end
  end
end
