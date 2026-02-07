# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class ClustersController < ApplicationController
          include AuditLogging

          before_action :set_cluster, only: %i[show update destroy test_connection sync health]

          # GET /api/v1/devops/swarm/clusters
          def index
            scope = current_user.account.devops_swarm_clusters

            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.by_environment(params[:environment]) if params[:environment].present?
            scope = scope.order(created_at: :desc)

            render_success(items: scope.map(&:cluster_summary))
            log_audit_event("swarm.clusters.list", current_user.account)
          end

          # GET /api/v1/devops/swarm/clusters/:id
          def show
            render_success(cluster: @cluster.cluster_details)
            log_audit_event("swarm.clusters.read", @cluster)
          end

          # POST /api/v1/devops/swarm/clusters
          def create
            manager = ::Devops::Docker::SwarmManager.new(account: current_user.account)

            begin
              cluster = manager.register_cluster(cluster_params)
              render_success({ cluster: cluster.cluster_details }, status: :created)
              log_audit_event("swarm.clusters.create", cluster)
            rescue ::Devops::Docker::ApiClient::ConnectionError => e
              render_error("Connection failed: #{e.message}", status: :unprocessable_entity)
            rescue ActiveRecord::RecordInvalid => e
              render_error(e.message, status: :unprocessable_entity)
            end
          end

          # PATCH /api/v1/devops/swarm/clusters/:id
          def update
            if @cluster.update(cluster_params)
              render_success(cluster: @cluster.cluster_details)
              log_audit_event("swarm.clusters.update", @cluster)
            else
              render_error(@cluster.errors.full_messages.join(", "), status: :unprocessable_entity)
            end
          end

          # DELETE /api/v1/devops/swarm/clusters/:id
          def destroy
            manager = ::Devops::Docker::SwarmManager.new(account: current_user.account)
            manager.remove_cluster(@cluster)

            render_success(message: "Cluster removed successfully")
            log_audit_event("swarm.clusters.delete", @cluster)
          end

          # POST /api/v1/devops/swarm/clusters/:id/test_connection
          def test_connection
            manager = ::Devops::Docker::SwarmManager.new(account: current_user.account)

            begin
              result = manager.test_connection(@cluster)
              if result[:success]
                render_success(connected: true, message: "Connected (Docker #{result[:server_version]}, API #{result[:api_version]})")
              else
                render_success(connected: false, message: result[:error])
              end
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Connection test failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:id/sync
          def sync
            manager = ::Devops::Docker::SwarmManager.new(account: current_user.account)

            begin
              manager.sync_cluster(@cluster)
              render_success(cluster: @cluster.reload.cluster_details)
              log_audit_event("swarm.clusters.sync", @cluster)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Sync failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          # GET /api/v1/devops/swarm/clusters/:id/health
          def health
            monitor = ::Devops::Docker::HealthMonitor.new(cluster: @cluster)

            begin
              result = monitor.check_health
              render_success(health: result)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Health check failed: #{e.message}", status: :unprocessable_entity)
            end
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:id])
          end

          def cluster_params
            permitted = params.require(:cluster).permit(
              :name, :description, :api_endpoint, :api_version,
              :environment, :auto_sync, :sync_interval_seconds,
              :encryption_key_id, :tls_verify,
              :tls_ca, :tls_cert, :tls_key,
              metadata: {}
            )

            build_tls_credentials(permitted)
          end

          def build_tls_credentials(permitted)
            tls_ca = permitted.delete(:tls_ca)
            tls_cert = permitted.delete(:tls_cert)
            tls_key = permitted.delete(:tls_key)

            if tls_ca.present? || tls_cert.present? || tls_key.present?
              permitted[:encrypted_tls_credentials] = {
                ca_cert: tls_ca,
                client_cert: tls_cert,
                client_key: tls_key
              }.to_json
            end

            permitted
          end
        end
      end
    end
  end
end
