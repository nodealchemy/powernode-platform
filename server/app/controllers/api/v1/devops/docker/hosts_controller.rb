# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Docker
        class HostsController < ApplicationController
          include AuditLogging

          before_action :set_host, only: %i[show update destroy test_connection sync health]

          # GET /api/v1/devops/docker/hosts
          def index
            scope = current_user.account.devops_docker_hosts

            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.by_environment(params[:environment]) if params[:environment].present?
            scope = scope.order(created_at: :desc)

            render_success(items: scope.map(&:host_summary))
            log_audit_event("docker.hosts.list", current_user.account)
          end

          # GET /api/v1/devops/docker/hosts/:id
          def show
            render_success(host: @host.host_details)
            log_audit_event("docker.hosts.read", @host)
          end

          # POST /api/v1/devops/docker/hosts
          def create
            manager = ::Devops::Docker::HostManager.new(account: current_user.account)

            begin
              host = manager.register_host(host_params)
              render_success({ host: host.host_details }, status: :created)
              log_audit_event("docker.hosts.create", host)
            rescue ::Devops::Docker::ApiClient::ConnectionError => e
              render_error("Connection failed: #{e.message}", status: :unprocessable_content)
            rescue ActiveRecord::RecordInvalid => e
              render_error(e.message, status: :unprocessable_content)
            end
          end

          # PATCH /api/v1/devops/docker/hosts/:id
          def update
            if @host.update(host_params)
              render_success(host: @host.host_details)
              log_audit_event("docker.hosts.update", @host)
            else
              render_error(@host.errors.full_messages.join(", "), status: :unprocessable_content)
            end
          end

          # DELETE /api/v1/devops/docker/hosts/:id
          def destroy
            manager = ::Devops::Docker::HostManager.new(account: current_user.account)
            manager.remove_host(@host)

            render_success(message: "Docker host removed successfully")
            log_audit_event("docker.hosts.delete", @host)
          end

          # POST /api/v1/devops/docker/hosts/:id/test_connection
          def test_connection
            manager = ::Devops::Docker::HostManager.new(account: current_user.account)

            begin
              result = manager.test_connection(@host)
              if result[:success]
                render_success(connection: { success: true, message: "Connected (Docker #{result[:server_version]}, API #{result[:api_version]})" })
              else
                render_success(connection: { success: false, message: result[:error] })
              end
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Connection test failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/docker/hosts/:id/sync
          def sync
            manager = ::Devops::Docker::HostManager.new(account: current_user.account)

            begin
              manager.sync_host(@host)
              render_success(host: @host.reload.host_details)
              log_audit_event("docker.hosts.sync", @host)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Sync failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # GET /api/v1/devops/docker/hosts/:id/health
          def health
            host_data = {
              host_id: @host.id,
              status: @host.status,
              container_health: {
                total: @host.docker_containers.count,
                running: @host.docker_containers.running.count,
                stopped: @host.docker_containers.stopped.count,
                paused: @host.docker_containers.where(state: "paused").count
              },
              image_stats: {
                total: @host.docker_images.count,
                dangling: @host.docker_images.dangling.count
              },
              recent_events: {
                critical: @host.docker_events.critical.since(24.hours.ago).count,
                warning: @host.docker_events.by_severity("warning").since(24.hours.ago).count,
                unacknowledged: @host.docker_events.unacknowledged.count
              },
              resource_usage: {
                memory_bytes: @host.memory_bytes,
                cpu_count: @host.cpu_count,
                storage_bytes: @host.storage_bytes
              }
            }

            render_success(health: host_data)
          end

          private

          def set_host
            @host = current_user.account.devops_docker_hosts.find(params[:id])
          end

          def host_params
            permitted = params.require(:host).permit(
              :name, :description, :api_endpoint, :api_version,
              :environment, :auto_sync, :sync_interval_seconds,
              :tls_verify, :encryption_key_id,
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
