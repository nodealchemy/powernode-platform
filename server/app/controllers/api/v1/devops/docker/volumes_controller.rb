# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Docker
        class VolumesController < ApplicationController
          include AuditLogging

          before_action :set_host

          # GET /api/v1/devops/docker/hosts/:host_id/volumes
          def index
            client = ::Devops::Docker::ApiClient.new(@host)

            begin
              result = client.volume_list
              volumes = result.is_a?(Hash) ? (result["Volumes"] || []) : result
              render_success(items: volumes)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch volumes: #{e.message}", status: :unprocessable_content)
            end
          end

          # GET /api/v1/devops/docker/hosts/:host_id/volumes/:id
          def show
            client = ::Devops::Docker::ApiClient.new(@host)

            begin
              volume = client.volume_inspect(params[:id])
              render_success(volume: volume)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Volume not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch volume: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/docker/hosts/:host_id/volumes
          def create
            client = ::Devops::Docker::ApiClient.new(@host)

            begin
              result = client.volume_create(volume_params)
              render_success({ volume: result }, status: :created)
              log_audit_event("docker.volumes.create", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Volume creation failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # DELETE /api/v1/devops/docker/hosts/:host_id/volumes/:id
          def destroy
            client = ::Devops::Docker::ApiClient.new(@host)

            begin
              client.volume_delete(params[:id])
              render_success(message: "Volume removed successfully")
              log_audit_event("docker.volumes.delete", @host)
            rescue ::Devops::Docker::ApiClient::NotFoundError
              render_error("Volume not found", status: :not_found)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Volume removal failed: #{e.message}", status: :unprocessable_content)
            end
          end

          private

          def set_host
            @host = current_user.account.devops_docker_hosts.find(params[:host_id])
          end

          def volume_params
            params.require(:volume).permit(:name, :driver, Labels: {}, DriverOpts: {}).to_h
          end
        end
      end
    end
  end
end
