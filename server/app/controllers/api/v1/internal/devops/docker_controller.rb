# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Devops
        class DockerController < InternalBaseController
          include Api::V1::Internal::WorkerTenancy

          # GET /api/v1/internal/devops/docker/hosts
          def index
            hosts = host_scope.auto_syncable

            render_success(
              hosts: hosts.map { |h|
                {
                  id: h.id,
                  name: h.name,
                  api_endpoint: h.api_endpoint,
                  api_version: h.api_version,
                  sync_interval_seconds: h.sync_interval_seconds,
                  last_synced_at: h.last_synced_at
                }
              }
            )
          end

          # GET /api/v1/internal/devops/docker/hosts/:id/connection
          def connection
            host = host_scope.find(params[:id])

            render_success(
              connection: {
                host_id: host.id,
                api_endpoint: host.api_endpoint,
                api_version: host.api_version,
                encrypted_tls_credentials: host.encrypted_tls_credentials,
                encryption_key_id: host.encryption_key_id,
                tls_verify: host.tls_verify
              }
            )
          rescue ActiveRecord::RecordNotFound
            render_error("Host not found", status: :not_found)
          end

          # POST /api/v1/internal/devops/docker/hosts/:id/sync_results
          def sync_results
            host = host_scope.find(params[:id])

            ActiveRecord::Base.transaction do
              sync_containers(host, params[:containers]) if params[:containers].present?
              sync_images(host, params[:images]) if params[:images].present?

              host.update!(
                container_count: host.docker_containers.count,
                image_count: host.docker_images.count,
                last_synced_at: Time.current,
                status: "connected",
                consecutive_failures: 0
              )
            end

            render_success({ status: "ok" })
            log_internal_audit("docker.host.sync", "DockerHost", host.id, account_id: host.account_id)
          rescue ActiveRecord::RecordNotFound
            render_error("Host not found", status: :not_found)
          rescue StandardError => e
            Rails.logger.error "Docker sync error: #{e.message}"
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/internal/devops/docker/hosts/:id/health_results
          def health_results
            host = host_scope.find(params[:id])

            if params[:status] == "healthy"
              host.record_success!
            else
              host.record_failure!
            end

            if params[:alerts].present?
              params[:alerts].each do |alert|
                host.docker_events.create!(
                  event_type: alert[:type] || "health_check",
                  severity: alert[:severity] || "warning",
                  source_type: alert[:source_type] || "host",
                  source_id: alert[:source_id],
                  source_name: alert[:source_name],
                  message: alert[:message],
                  metadata: alert[:metadata]&.to_unsafe_h || {}
                )
              end
            end

            render_success({ status: "ok" })
          rescue ActiveRecord::RecordNotFound
            render_error("Host not found", status: :not_found)
          rescue StandardError => e
            Rails.logger.error "Docker health results error: #{e.message}"
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/internal/devops/docker/events
          def create_event
            if params[:action_type] == "cleanup"
              days = (params[:older_than_days] || 30).to_i
              # Anchored to the calling worker's account: `older_than_days` is
              # caller-controlled (0/negative purges everything), so an unscoped
              # delete_all let a forged worker CN destroy EVERY tenant's event
              # history. devops_docker_events has no account_id column; scope via
              # the host_scope (worker's own hosts). See WorkerTenancy.
              count = ::Devops::DockerEvent
                .where(docker_host_id: host_scope.select(:id))
                .where(acknowledged: true)
                .where("created_at < ?", days.days.ago)
                .delete_all

              render_success(deleted_count: count)
            else
              host = host_scope.find(params[:docker_host_id])
              event = host.docker_events.create!(
                event_type: params[:event_type],
                severity: params[:severity] || "info",
                source_type: params[:source_type],
                source_id: params[:source_id],
                source_name: params[:source_name],
                message: params[:message],
                metadata: params[:metadata]&.to_unsafe_h || {}
              )

              render_success(event_id: event.id)
            end
          rescue ActiveRecord::RecordNotFound
            render_error("Host not found", status: :not_found)
          rescue StandardError => e
            Rails.logger.error "Docker event creation error: #{e.message}"
            render_error(e.message, status: :unprocessable_content)
          end

          private

          # Tenancy scope: docker hosts owned by the authenticated worker's
          # account. #connection renders `encrypted_tls_credentials` +
          # `encryption_key_id` (control-plane material), and the sync/health/
          # event actions mutate host state, so a bare `find` disclosed and let
          # a forged worker mutate any tenant's host by enumerable id.
          # `devops_docker_hosts.account_id` is NOT NULL, so a nil worker
          # account_id (fail-closed) catches no rows. Cross-account id -> 404,
          # never 403. See Api::V1::Internal::WorkerTenancy.
          def host_scope
            ::Devops::DockerHost.where(account_id: worker_account_id)
          end

          def sync_containers(host, containers_data)
            incoming_ids = containers_data.map { |c| c[:docker_container_id] || c["docker_container_id"] }

            # Remove containers that no longer exist on the host
            host.docker_containers.where.not(docker_container_id: incoming_ids).destroy_all

            # Upsert all containers from sync data
            containers_data.each do |data|
              data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)
              docker_id = data["docker_container_id"] || data[:docker_container_id]

              container = host.docker_containers.find_or_initialize_by(docker_container_id: docker_id)

              container.assign_attributes(
                name: data["name"] || "unknown",
                image: data["image"] || "unknown",
                image_id: data["image_id"],
                state: data["state"] || "created",
                status_text: data["status_text"],
                ports: data["ports"] || [],
                mounts: data["mounts"] || [],
                networks: data["networks"] || {},
                labels: data["labels"] || {},
                command: data["command"],
                last_seen_at: Time.current
              )
              container.save!
            end
          end

          def sync_images(host, images_data)
            incoming_ids = images_data.map { |i| i[:docker_image_id] || i["docker_image_id"] }

            # Remove images that no longer exist on the host
            host.docker_images.where.not(docker_image_id: incoming_ids).destroy_all

            # Upsert all images from sync data
            images_data.each do |data|
              data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)
              docker_id = data["docker_image_id"] || data[:docker_image_id]

              image = host.docker_images.find_or_initialize_by(docker_image_id: docker_id)

              image.assign_attributes(
                repo_tags: data["repo_tags"] || [],
                repo_digests: data["repo_digests"] || [],
                size_bytes: data["size_bytes"],
                virtual_size: data["virtual_size"],
                container_count: data["container_count"] || 0,
                labels: data["labels"] || {},
                docker_created_at: data["docker_created_at"],
                last_seen_at: Time.current
              )
              image.save!
            end
          end
        end
      end
    end
  end
end
