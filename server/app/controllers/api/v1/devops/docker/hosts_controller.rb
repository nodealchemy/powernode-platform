# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Docker
        class HostsController < ApplicationController
          include AuditLogging
          include ::Ai::GatedActions
          include ::Devops::TlsCredentialParams

          # test_connection is a read-effect connectivity probe (no host mutation).
          before_action -> { require_permission("devops.docker.read") }, only: %i[index show health test_connection]
          before_action -> { require_permission("devops.docker.manage") }, only: %i[create update destroy sync]
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
          #
          # A MANAGED host is a platform-provisioned Docker daemon: tearing it
          # down purges Vault-held mTLS material and orphans whatever runs on
          # it, so it is ADDITIONALLY gated through Ai::AutonomyGate on
          # `system.runtime_docker_decommission` — the SAME action category the
          # MCP surface uses, so one operator policy governs both. Before
          # IMP-20fb59ec849d this endpoint reached the same host with a bare
          # destroy!, and the control an operator set was honoured on the MCP
          # path and silently skipped here.
          #
          # An EXTERNAL host is an operator-registered pointer at a daemon the
          # platform does not own; removing the registration destroys a row and
          # nothing else. Its MCP twin resolves managed hosts only, so that
          # category expresses no opinion about it — gating it would park every
          # ordinary registration removal for approval.
          #
          # AUDIT: `on_proceed` runs only on the proceed branch, so the
          # request-context `docker.hosts.delete` event is written when the
          # teardown happens inline and not when it is parked (nothing has been
          # deleted yet) or blocked (nothing will be). A teardown that lands
          # later, on approval, is audited by Devops::DockerHost's `Auditable`
          # before_destroy hook instead — a row on every path, without the HTTP
          # request context, which by then belongs to the approver's request
          # rather than this one.
          def destroy
            return destroy_now unless @host.managed?

            host_id = @host.id
            host_name = @host.name

            gate!(
              action_category: "system.runtime_docker_decommission",
              executor_class: "Devops::Docker::Executors::DecommissionHost",
              params: { host_id: host_id },
              source_type: "Devops::DockerHost",
              source_id: host_id,
              description: "Decommission managed Docker host '#{host_name}'",
              on_proceed: ->(_result) {
                render_success(message: "Docker host removed successfully")
                log_audit_event("docker.hosts.delete", @host)
              }
            )
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

          # Ungated teardown, for a host whose removal is a registration edit.
          # Still routed through HostManager rather than #destroy! so the
          # managed/external branch has exactly one home.
          def destroy_now
            manager = ::Devops::Docker::HostManager.new(account: current_user.account)
            manager.remove_host(@host)

            render_success(message: "Docker host removed successfully")
            log_audit_event("docker.hosts.delete", @host)
          end

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
        end
      end
    end
  end
end
