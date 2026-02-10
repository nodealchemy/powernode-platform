# frozen_string_literal: true

module Api
  module V1
    module Internal
      class SwarmController < InternalBaseController
        # GET /api/v1/internal/swarm/clusters
        def index
          clusters = ::Devops::SwarmCluster.auto_syncable

          if params[:auto_sync] == "true"
            clusters = clusters.where(auto_sync: true)
          end

          render_success(
            items: clusters.map { |c|
              {
                id: c.id,
                name: c.name,
                api_endpoint: c.api_endpoint,
                api_version: c.api_version,
                sync_interval_seconds: c.sync_interval_seconds,
                last_synced_at: c.last_synced_at
              }
            }
          )
        end

        # GET /api/v1/internal/swarm/clusters/:id/connection
        def connection
          cluster = ::Devops::SwarmCluster.find(params[:id])

          render_success(
            cluster_id: cluster.id,
            api_endpoint: cluster.api_endpoint,
            api_version: cluster.api_version,
            encrypted_tls_credentials: cluster.encrypted_tls_credentials,
            encryption_key_id: cluster.encryption_key_id
          )
        rescue ActiveRecord::RecordNotFound
          render_error("Cluster not found", status: :not_found)
        end

        # POST /api/v1/internal/swarm/clusters/:id/sync_results
        def sync_results
          cluster = ::Devops::SwarmCluster.find(params[:id])

          ActiveRecord::Base.transaction do
            sync_nodes(cluster, params[:nodes]) if params[:nodes].present?
            sync_services(cluster, params[:services]) if params[:services].present?

            cluster.update!(
              node_count: cluster.swarm_nodes.count,
              service_count: cluster.swarm_services.count,
              last_synced_at: Time.current,
              status: "connected",
              consecutive_failures: 0
            )
          end

          render_success(status: "ok")
          log_internal_audit("swarm.cluster.sync", "SwarmCluster", cluster.id, account_id: cluster.account_id)
        rescue ActiveRecord::RecordNotFound
          render_error("Cluster not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Swarm sync error: #{e.message}"
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/internal/swarm/clusters/:id/health_results
        def health_results
          cluster = ::Devops::SwarmCluster.find(params[:id])

          if params[:status] == "healthy"
            cluster.record_success!
          else
            cluster.record_failure!
          end

          # Create events for any alerts
          if params[:alerts].present?
            params[:alerts].each do |alert|
              cluster.swarm_events.create!(
                event_type: alert[:type] || "health_check",
                severity: alert[:severity] || "warning",
                source_type: alert[:source_type] || "cluster",
                source_id: alert[:source_id],
                source_name: alert[:source_name],
                message: alert[:message],
                metadata: alert[:metadata] || {}
              )
            end
          end

          render_success(status: "ok")
        rescue ActiveRecord::RecordNotFound
          render_error("Cluster not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Swarm health results error: #{e.message}"
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH /api/v1/internal/swarm/deployments/:id
        def update_deployment
          deployment = ::Devops::SwarmDeployment.find(params[:id])

          case params[:status]
          when "running"
            deployment.start!
          when "completed"
            deployment.complete!(params[:result]&.to_unsafe_h || {})
          when "failed"
            deployment.fail!(params[:result]&.to_unsafe_h || {})
          end

          render_success(status: "ok")
        rescue ActiveRecord::RecordNotFound
          render_error("Deployment not found", status: :not_found)
        end

        # POST /api/v1/internal/swarm/events
        def create_event
          if params[:action_type] == "cleanup"
            days = (params[:older_than_days] || 30).to_i
            count = ::Devops::SwarmEvent
              .where(acknowledged: true)
              .where("created_at < ?", days.days.ago)
              .delete_all

            render_success(deleted_count: count)
          else
            cluster = ::Devops::SwarmCluster.find(params[:cluster_id])
            event = cluster.swarm_events.create!(
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
          render_error("Cluster not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Swarm event creation error: #{e.message}"
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def sync_nodes(cluster, nodes_data)
          existing_node_ids = cluster.swarm_nodes.pluck(:docker_node_id)
          incoming_node_ids = nodes_data.map { |n| n[:docker_node_id] || n["docker_node_id"] }

          # Remove nodes no longer in swarm
          cluster.swarm_nodes.where.not(docker_node_id: incoming_node_ids).destroy_all

          # Upsert nodes
          nodes_data.each do |node_data|
            node_data = node_data.to_unsafe_h if node_data.respond_to?(:to_unsafe_h)
            docker_id = node_data["docker_node_id"] || node_data[:docker_node_id]

            node = cluster.swarm_nodes.find_or_initialize_by(docker_node_id: docker_id)
            node.assign_attributes(
              hostname: node_data["hostname"],
              role: node_data["role"],
              availability: node_data["availability"],
              status: node_data["status"],
              manager_status: node_data["manager_status"],
              ip_address: node_data["ip_address"],
              engine_version: node_data["engine_version"],
              os: node_data["os"],
              architecture: node_data["architecture"],
              memory_bytes: node_data["memory_bytes"],
              cpu_count: node_data["cpu_count"],
              labels: node_data["labels"] || {},
              last_seen_at: Time.current
            )
            node.save!
          end
        end

        def sync_services(cluster, services_data)
          incoming_ids = services_data.map { |s| s[:docker_service_id] || s["docker_service_id"] }

          # Remove imported services that no longer exist in Docker
          cluster.swarm_services.where.not(docker_service_id: incoming_ids).destroy_all

          # Only update already-imported services (do not create new ones)
          imported_ids = cluster.swarm_services.pluck(:docker_service_id)

          services_data.each do |svc_data|
            svc_data = svc_data.to_unsafe_h if svc_data.respond_to?(:to_unsafe_h)
            docker_id = svc_data["docker_service_id"] || svc_data[:docker_service_id]

            next unless imported_ids.include?(docker_id)

            service = cluster.swarm_services.find_by(docker_service_id: docker_id)
            next unless service

            service.assign_attributes(
              service_name: svc_data["service_name"],
              image: svc_data["image"],
              mode: svc_data["mode"] || "replicated",
              desired_replicas: svc_data["desired_replicas"] || 1,
              running_replicas: svc_data["running_replicas"] || 0,
              ports: svc_data["ports"] || [],
              constraints: svc_data["constraints"] || [],
              resource_limits: svc_data["resource_limits"] || {},
              resource_reservations: svc_data["resource_reservations"] || {},
              update_config: svc_data["update_config"] || {},
              rollback_config: svc_data["rollback_config"] || {},
              labels: svc_data["labels"] || {},
              environment: svc_data["environment"] || [],
              version: svc_data["version"]
            )

            # Link to stack if labeled
            stack_name = (svc_data["labels"] || {})["com.docker.stack.namespace"]
            if stack_name.present?
              stack = cluster.swarm_stacks.find_by(name: stack_name)
              service.stack = stack if stack
            end

            service.save!
          end
        end
      end
    end
  end
end
