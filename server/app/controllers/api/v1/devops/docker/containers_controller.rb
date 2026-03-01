# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Docker
        class ContainersController < ApplicationController
          include AuditLogging

          before_action :set_host
          before_action :set_container, only: %i[show destroy start stop restart logs stats]

          # GET /api/v1/devops/docker/hosts/:host_id/containers
          def index
            scope = @host.docker_containers

            scope = scope.by_state(params[:state]) if params[:state].present?
            scope = scope.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
            scope = scope.order(created_at: :desc)

            render_success(items: scope.map(&:container_summary))
          end

          # GET /api/v1/devops/docker/hosts/:host_id/containers/available
          def available
            manager = ::Devops::Docker::HostManager.new(account: current_user.account)

            begin
              containers = manager.available_containers(@host)
              render_success(items: containers)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch available containers: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/docker/hosts/:host_id/containers/import
          def import
            docker_container_ids = Array(params[:docker_container_ids])

            if docker_container_ids.empty?
              return render_error("No container IDs provided", status: :unprocessable_content)
            end

            manager = ::Devops::Docker::HostManager.new(account: current_user.account)

            begin
              imported = manager.import_containers(@host, docker_container_ids)
              render_success(
                items: imported.map(&:container_summary),
                imported_count: imported.size
              )
              log_audit_event("docker.containers.import", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Import failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # GET /api/v1/devops/docker/hosts/:host_id/containers/:id
          def show
            render_success(container: @container.container_details)
          end

          # POST /api/v1/devops/docker/hosts/:host_id/containers
          def create
            manager = ::Devops::Docker::ContainerManager.new(host: @host, user: current_user)

            begin
              container_data = params.require(:container)
              result = manager.create_container(
                name: container_data[:name],
                image: container_data[:image],
                params: container_create_params
              )
              render_success({ container: result }, status: :created)
              log_audit_event("docker.containers.create", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Container creation failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # DELETE /api/v1/devops/docker/hosts/:host_id/containers/:id
          def destroy
            manager = ::Devops::Docker::ContainerManager.new(host: @host, user: current_user)

            begin
              manager.remove_container(@container, force: params[:force] == "true")
              render_success(message: "Container removed successfully")
              log_audit_event("docker.containers.delete", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Container removal failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/docker/hosts/:host_id/containers/:id/start
          def start
            manager = ::Devops::Docker::ContainerManager.new(host: @host, user: current_user)

            begin
              container = manager.start_container(@container)
              render_success(container: container.container_details)
              log_audit_event("docker.containers.start", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Container start failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/docker/hosts/:host_id/containers/:id/stop
          def stop
            manager = ::Devops::Docker::ContainerManager.new(host: @host, user: current_user)

            begin
              container = manager.stop_container(@container, timeout: (params[:timeout] || 10).to_i)
              render_success(container: container.container_details)
              log_audit_event("docker.containers.stop", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Container stop failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/docker/hosts/:host_id/containers/:id/restart
          def restart
            manager = ::Devops::Docker::ContainerManager.new(host: @host, user: current_user)

            begin
              container = manager.restart_container(@container, timeout: (params[:timeout] || 10).to_i)
              render_success(container: container.container_details)
              log_audit_event("docker.containers.restart", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Container restart failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # GET /api/v1/devops/docker/hosts/:host_id/containers/:id/logs
          def logs
            manager = ::Devops::Docker::ContainerManager.new(host: @host)

            begin
              log_entries = manager.container_logs(@container, log_opts)
              render_success(logs: log_entries)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch logs: #{e.message}", status: :unprocessable_content)
            end
          end

          # GET /api/v1/devops/docker/hosts/:host_id/containers/:id/stats
          def stats
            manager = ::Devops::Docker::ContainerManager.new(host: @host)

            begin
              result = manager.container_stats(@container)
              render_success(stats: result)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch stats: #{e.message}", status: :unprocessable_content)
            end
          end

          private

          def set_host
            @host = current_user.account.devops_docker_hosts.find(params[:host_id])
          end

          def set_container
            @container = @host.docker_containers.find(params[:id])
          end

          def container_create_params
            params.require(:container).permit(:command, :restart_policy, labels: {}, environment: {}, ports: {}, volumes: {}).to_h
          end

          def log_opts
            {
              tail: params[:tail] || "100",
              since: params[:since],
              timestamps: params[:timestamps] != "false",
              stdout: params[:stdout] != "false",
              stderr: params[:stderr] != "false"
            }
          end
        end
      end
    end
  end
end
