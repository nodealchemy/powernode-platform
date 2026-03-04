# frozen_string_literal: true

module Devops
  module Docker
    class ServiceManager
      def initialize(cluster:, user: nil)
        @cluster = cluster
        @user = user
        @client = ApiClient.new(cluster)
      end

      def create_service(params)
        spec = build_service_spec(params)
        deployment = create_deployment("deploy", desired_state: params.to_h)

        begin
          result = @client.service_create(spec)
          docker_service_id = result["ID"]

          docker_service = @client.service_inspect(docker_service_id)
          service = sync_single_service(docker_service)

          complete_deployment(deployment, result: { docker_service_id: docker_service_id })
          Rails.logger.info("Created service #{params[:service_name]} on cluster #{@cluster.name}")
          service
        rescue ApiClient::ApiError => e
          fail_deployment(deployment, error: e.message)
          raise
        end
      end

      def update_service(service, params)
        docker_service = @client.service_inspect(service.docker_service_id)
        version = docker_service.dig("Version", "Index")

        deployment = create_deployment("update",
          service: service,
          previous_state: docker_service["Spec"],
          desired_state: params
        )

        begin
          @client.service_update(service.docker_service_id, version, params)

          # Re-fetch and sync updated state
          updated = @client.service_inspect(service.docker_service_id)
          sync_single_service(updated, existing: service)

          complete_deployment(deployment)
          Rails.logger.info("Updated service #{service.service_name} on cluster #{@cluster.name}")
          { success: true, service: service.reload, deployment: deployment }
        rescue ApiClient::ApiError => e
          fail_deployment(deployment, error: e.message)
          Rails.logger.error("Failed to update service #{service.service_name}: #{e.message}")
          { success: false, error: e.message, deployment: deployment }
        end
      end

      def scale_service(service, replicas)
        docker_service = @client.service_inspect(service.docker_service_id)
        version = docker_service.dig("Version", "Index")
        spec = docker_service["Spec"] || {}

        previous_replicas = spec.dig("Mode", "Replicated", "Replicas")
        spec["Mode"] ||= {}
        spec["Mode"]["Replicated"] ||= {}
        spec["Mode"]["Replicated"]["Replicas"] = replicas.to_i

        deployment = create_deployment("scale",
          service: service,
          previous_state: { replicas: previous_replicas },
          desired_state: { replicas: replicas.to_i }
        )

        begin
          @client.service_update(service.docker_service_id, version, spec)
          service.update!(desired_replicas: replicas.to_i)

          complete_deployment(deployment)
          Rails.logger.info("Scaled service #{service.service_name} to #{replicas} replicas")
          { success: true, service: service, deployment: deployment }
        rescue ApiClient::ApiError => e
          fail_deployment(deployment, error: e.message)
          Rails.logger.error("Failed to scale service #{service.service_name}: #{e.message}")
          { success: false, error: e.message, deployment: deployment }
        end
      end

      def rollback_service(service)
        docker_service = @client.service_inspect(service.docker_service_id)
        version = docker_service.dig("Version", "Index")
        previous_spec = docker_service.dig("PreviousSpec")

        unless previous_spec
          return { success: false, error: "No previous version available for rollback" }
        end

        deployment = create_deployment("rollback",
          service: service,
          previous_state: docker_service["Spec"],
          desired_state: previous_spec
        )

        begin
          @client.service_update(service.docker_service_id, version, previous_spec)

          updated = @client.service_inspect(service.docker_service_id)
          sync_single_service(updated, existing: service)

          complete_deployment(deployment)
          Rails.logger.info("Rolled back service #{service.service_name}")
          { success: true, service: service.reload, deployment: deployment }
        rescue ApiClient::ApiError => e
          fail_deployment(deployment, error: e.message)
          Rails.logger.error("Failed to rollback service #{service.service_name}: #{e.message}")
          { success: false, error: e.message, deployment: deployment }
        end
      end

      def remove_service(service)
        deployment = create_deployment("remove",
          service: service,
          previous_state: { service_name: service.service_name, image: service.image }
        )

        begin
          @client.service_delete(service.docker_service_id)
          service.destroy!

          complete_deployment(deployment)
          Rails.logger.info("Removed service #{service.service_name} from cluster #{@cluster.name}")
          { success: true, deployment: deployment }
        rescue ApiClient::ApiError => e
          fail_deployment(deployment, error: e.message)
          Rails.logger.error("Failed to remove service #{service.service_name}: #{e.message}")
          { success: false, error: e.message, deployment: deployment }
        end
      end

      def service_logs(service, opts = {})
        @client.service_logs(service.docker_service_id, opts)
      end

      def list_tasks(service)
        filters = { service: [service.docker_service_id] }
        @client.task_list(filters)
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to list tasks for service #{service.service_name}: #{e.message}")
        { success: false, error: e.message }
      end

      private

      def create_deployment(type, service: nil, stack: nil, previous_state: {}, desired_state: {})
        @cluster.swarm_deployments.create!(
          deployment_type: type,
          service: service,
          stack: stack,
          triggered_by: @user,
          status: "running",
          previous_state: previous_state,
          desired_state: desired_state,
          started_at: Time.current,
          trigger_source: "api"
        )
      end

      def complete_deployment(deployment, result: {})
        deployment.update!(
          status: "completed",
          result: result,
          completed_at: Time.current,
          duration_ms: ((Time.current - deployment.started_at) * 1000).to_i
        )
      end

      def fail_deployment(deployment, error:)
        deployment.update!(
          status: "failed",
          result: { error: error },
          completed_at: Time.current,
          duration_ms: ((Time.current - deployment.started_at) * 1000).to_i
        )
      end

      def sync_single_service(docker_service, existing: nil)
        spec = docker_service["Spec"] || {}
        task_template = spec["TaskTemplate"] || {}

        service = existing || @cluster.swarm_services.find_or_initialize_by(
          docker_service_id: docker_service["ID"]
        )

        service.assign_attributes(
          service_name: spec["Name"] || "unknown",
          image: task_template.dig("ContainerSpec", "Image") || "unknown",
          mode: spec.dig("Mode", "Replicated") ? "replicated" : "global",
          desired_replicas: spec.dig("Mode", "Replicated", "Replicas") || 1,
          ports: extract_ports(spec["EndpointSpec"]),
          constraints: task_template.dig("Placement", "Constraints") || [],
          resource_limits: task_template.dig("Resources", "Limits") || {},
          resource_reservations: task_template.dig("Resources", "Reservations") || {},
          update_config: spec["UpdateConfig"] || {},
          rollback_config: spec["RollbackConfig"] || {},
          labels: spec["Labels"] || {},
          environment: task_template.dig("ContainerSpec", "Env") || [],
          version: docker_service.dig("Version", "Index")
        )
        service.save!
        service
      end

      def build_service_spec(params)
        spec = {
          "Name" => params[:service_name],
          "TaskTemplate" => {
            "ContainerSpec" => {
              "Image" => params[:image]
            }
          }
        }

        container_spec = spec["TaskTemplate"]["ContainerSpec"]
        container_spec["Env"] = Array(params[:environment]) if params[:environment].present?

        if params[:constraints].present?
          spec["TaskTemplate"]["Placement"] = { "Constraints" => Array(params[:constraints]) }
        end

        if params[:resource_limits].present? || params[:resource_reservations].present?
          spec["TaskTemplate"]["Resources"] = {}
          spec["TaskTemplate"]["Resources"]["Limits"] = params[:resource_limits].to_h if params[:resource_limits].present?
          spec["TaskTemplate"]["Resources"]["Reservations"] = params[:resource_reservations].to_h if params[:resource_reservations].present?
        end

        mode = params[:mode] || "replicated"
        replicas = (params[:desired_replicas] || 1).to_i
        spec["Mode"] = if mode == "global"
                         { "Global" => {} }
                       else
                         { "Replicated" => { "Replicas" => replicas } }
                       end

        if params[:ports].present?
          spec["EndpointSpec"] = {
            "Ports" => Array(params[:ports]).map do |p|
              {
                "Protocol" => p[:protocol] || "tcp",
                "TargetPort" => p[:target].to_i,
                "PublishedPort" => p[:published].to_i,
                "PublishMode" => "ingress"
              }
            end
          }
        end

        spec["Labels"] = params[:labels].to_h if params[:labels].present?
        spec["UpdateConfig"] = params[:update_config].to_h if params[:update_config].present?
        spec["RollbackConfig"] = params[:rollback_config].to_h if params[:rollback_config].present?

        spec
      end

      def extract_ports(endpoint_spec)
        return [] unless endpoint_spec

        (endpoint_spec["Ports"] || []).map do |port|
          {
            protocol: port["Protocol"],
            target: port["TargetPort"],
            published: port["PublishedPort"],
            mode: port["PublishMode"]
          }
        end
      end
    end
  end
end
