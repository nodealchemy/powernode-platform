# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class ServicesController < ApplicationController
          include AuditLogging

          before_action :set_cluster
          before_action :set_service, only: %i[show update destroy scale rollback logs tasks]

          # GET /api/v1/devops/swarm/clusters/:cluster_id/services
          def index
            scope = @cluster.swarm_services

            scope = scope.where(mode: params[:mode]) if params[:mode].present?
            scope = scope.for_stack(params[:stack_name]) if params[:stack_name].present?
            scope = scope.unhealthy if params[:unhealthy] == "true"
            scope = scope.order(service_name: :asc)

            render_success(items: scope.map(&:service_summary))
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/services/available
          def available
            manager = ::Devops::Docker::SwarmManager.new(account: current_user.account)

            begin
              services = manager.available_services(@cluster)
              render_success(items: services)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch available services: #{e.message}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/services/import
          def import
            docker_service_ids = Array(params[:docker_service_ids])

            if docker_service_ids.empty?
              return render_error("No service IDs provided", status: :unprocessable_entity)
            end

            manager = ::Devops::Docker::SwarmManager.new(account: current_user.account)

            begin
              imported = manager.import_services(@cluster, docker_service_ids)
              render_success(
                items: imported.map(&:service_summary),
                imported_count: imported.size
              )
              log_audit_event("swarm.services.import", @cluster)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Import failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/services/:id
          def show
            render_success(service: @service.service_details)
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/services
          def create
            manager = ::Devops::Docker::ServiceManager.new(cluster: @cluster, user: current_user)

            begin
              service = manager.create_service(service_params)
              render_success({ service: service.service_details }, status: :created)
              log_audit_event("swarm.services.create", service)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Service creation failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # PATCH /api/v1/devops/swarm/clusters/:cluster_id/services/:id
          def update
            manager = ::Devops::Docker::ServiceManager.new(cluster: @cluster, user: current_user)

            begin
              manager.update_service(@service, service_params)
              render_success(service: @service.reload.service_details)
              log_audit_event("swarm.services.update", @service)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Service update failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # DELETE /api/v1/devops/swarm/clusters/:cluster_id/services/:id
          def destroy
            manager = ::Devops::Docker::ServiceManager.new(cluster: @cluster, user: current_user)

            begin
              manager.remove_service(@service)
              render_success(message: "Service removed successfully")
              log_audit_event("swarm.services.delete", @service)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Service removal failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/services/:id/scale
          def scale
            manager = ::Devops::Docker::ServiceManager.new(cluster: @cluster, user: current_user)

            begin
              manager.scale_service(@service, params[:replicas].to_i)
              render_success(service: @service.reload.service_details)
              log_audit_event("swarm.services.scale", @service)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Scale failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/services/:id/rollback
          def rollback
            manager = ::Devops::Docker::ServiceManager.new(cluster: @cluster, user: current_user)

            begin
              manager.rollback_service(@service)
              render_success(service: @service.reload.service_details)
              log_audit_event("swarm.services.rollback", @service)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Rollback failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/services/:id/logs
          def logs
            manager = ::Devops::Docker::ServiceManager.new(cluster: @cluster)

            begin
              log_entries = manager.service_logs(@service, log_params)
              render_success(items: log_entries)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch logs: #{e.message}", status: :unprocessable_entity)
            end
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/services/:id/tasks
          def tasks
            manager = ::Devops::Docker::ServiceManager.new(cluster: @cluster)

            begin
              task_list = manager.list_tasks(@service)
              items = Array(task_list).map { |t| format_task(t) }
              render_success(items: items)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Failed to fetch tasks: #{e.message}", status: :unprocessable_entity)
            end
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:cluster_id])
          end

          def set_service
            @service = @cluster.swarm_services.find(params[:id])
          end

          def service_params
            params.require(:service).permit(
              :service_name, :image, :mode, :desired_replicas,
              ports: [:target, :published, :protocol],
              constraints: [],
              environment: [],
              labels: {},
              resource_limits: {},
              update_config: {},
              rollback_config: {}
            )
          end

          def log_params
            params.permit(:tail, :since, :timestamps, :follow)
          end

          def format_task(task)
            {
              id: task["ID"],
              docker_task_id: task["ID"],
              service_id: task.dig("ServiceID"),
              node_id: task.dig("NodeID"),
              slot: task["Slot"],
              status: task.dig("Status", "State") || "unknown",
              desired_state: task["DesiredState"] || "unknown",
              image: task.dig("Spec", "ContainerSpec", "Image") || "unknown",
              error: task.dig("Status", "Err"),
              created_at: task.dig("CreatedAt") || task.dig("Status", "Timestamp"),
              updated_at: task.dig("UpdatedAt") || task.dig("Status", "Timestamp")
            }
          end
        end
      end
    end
  end
end
