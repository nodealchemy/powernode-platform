# frozen_string_literal: true

module Ai
  module Tools
    class DockerServiceTool < BaseTool
      include Concerns::DockerContextResolvable

      REQUIRED_PERMISSION = "swarm.services.read"

      def self.definition
        {
          name: "docker_service_management",
          description: "Manage Docker Swarm services: list, inspect, create, update, scale, rollback, remove, logs, tasks",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name (auto-selects if only one)" },
            service_id: { type: "string", required: false, description: "Service UUID, docker_service_id, or service_name" },
            service_name: { type: "string", required: false, description: "Service name (for create)" },
            image: { type: "string", required: false, description: "Docker image (for create/update)" },
            replicas: { type: "integer", required: false, description: "Number of replicas (for scale)" },
            tail: { type: "string", required: false, description: "Number of log lines (default: 100)" },
            environment: { type: "array", required: false, description: "Environment variables as KEY=VALUE" },
            constraints: { type: "array", required: false, description: "Placement constraints" },
            ports: { type: "array", required: false, description: "Port mappings" },
            labels: { type: "object", required: false, description: "Service labels" },
            mode: { type: "string", required: false, description: "Service mode: replicated or global" },
            update_config: { type: "object", required: false, description: "Update configuration" },
            rollback_config: { type: "object", required: false, description: "Rollback configuration" },
            resource_limits: { type: "object", required: false, description: "Resource limits" },
            resource_reservations: { type: "object", required: false, description: "Resource reservations" }
          }
        }
      end

      def self.action_definitions
        {
          "docker_list_services" => {
            description: "List all Swarm services on a cluster with replica counts and health",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name (auto-selects if only one)" }
            }
          },
          "docker_get_service" => {
            description: "Get detailed information about a specific Swarm service",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              service_id: { type: "string", required: true, description: "Service UUID, docker_service_id, or service_name" }
            }
          },
          "docker_create_service" => {
            description: "Create a new Swarm service with specified image, replicas, ports, and environment",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              service_name: { type: "string", required: true, description: "Service name" },
              image: { type: "string", required: true, description: "Docker image" },
              replicas: { type: "integer", required: false, description: "Number of replicas (default: 1)" },
              mode: { type: "string", required: false, description: "replicated or global (default: replicated)" },
              environment: { type: "array", required: false, description: "Environment variables as KEY=VALUE" },
              ports: { type: "array", required: false, description: "Port mappings [{target: 80, published: 8080}]" },
              constraints: { type: "array", required: false, description: "Placement constraints" },
              labels: { type: "object", required: false, description: "Service labels" },
              resource_limits: { type: "object", required: false, description: "Resource limits" },
              resource_reservations: { type: "object", required: false, description: "Resource reservations" }
            }
          },
          "docker_update_service" => {
            description: "Update a Swarm service's configuration (image, env, constraints, etc.)",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              service_id: { type: "string", required: true, description: "Service UUID, docker_service_id, or service_name" },
              image: { type: "string", required: false, description: "New Docker image" },
              environment: { type: "array", required: false, description: "New environment variables" },
              constraints: { type: "array", required: false, description: "New placement constraints" },
              labels: { type: "object", required: false, description: "New labels" },
              resource_limits: { type: "object", required: false, description: "New resource limits" }
            }
          },
          "docker_scale_service" => {
            description: "Scale a Swarm service to a specific number of replicas",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              service_id: { type: "string", required: true, description: "Service UUID, docker_service_id, or service_name" },
              replicas: { type: "integer", required: true, description: "Desired number of replicas" }
            }
          },
          "docker_rollback_service" => {
            description: "Rollback a Swarm service to its previous version",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              service_id: { type: "string", required: true, description: "Service UUID, docker_service_id, or service_name" }
            }
          },
          "docker_remove_service" => {
            description: "Remove a Swarm service and its tasks",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              service_id: { type: "string", required: true, description: "Service UUID, docker_service_id, or service_name" }
            }
          },
          "docker_service_logs" => {
            description: "Retrieve logs from a Swarm service (aggregated from all tasks)",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              service_id: { type: "string", required: true, description: "Service UUID, docker_service_id, or service_name" },
              tail: { type: "string", required: false, description: "Number of lines from the end (default: 100)" }
            }
          },
          "docker_service_tasks" => {
            description: "List tasks (containers) for a Swarm service with their status and node placement",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              service_id: { type: "string", required: true, description: "Service UUID, docker_service_id, or service_name" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "docker_list_services" then list_services(params)
        when "docker_get_service" then get_service(params)
        when "docker_create_service" then create_service(params)
        when "docker_update_service" then update_service(params)
        when "docker_scale_service" then scale_service(params)
        when "docker_rollback_service" then rollback_service(params)
        when "docker_remove_service" then remove_service(params)
        when "docker_service_logs" then service_logs(params)
        when "docker_service_tasks" then service_tasks(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      rescue Devops::Docker::ApiClient::ApiError => e
        { success: false, error: "Docker API error: #{e.message}" }
      end

      private

      def list_services(params)
        cluster = resolve_cluster(params[:cluster_id])
        services = cluster.swarm_services.includes(:stack).order(:service_name)

        {
          success: true,
          cluster: { id: cluster.id, name: cluster.name },
          services: services.map { |s| s.service_summary },
          count: services.size
        }
      end

      def get_service(params)
        cluster = resolve_cluster(params[:cluster_id])
        service = resolve_service(cluster, params[:service_id])

        { success: true, service: service.service_details }
      end

      def create_service(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::ServiceManager.new(cluster: cluster, user: user)

        service_params = {
          service_name: params[:service_name],
          image: params[:image],
          mode: params[:mode] || "replicated",
          desired_replicas: params[:replicas] || 1,
          environment: params[:environment],
          ports: params[:ports],
          constraints: params[:constraints],
          labels: params[:labels],
          resource_limits: params[:resource_limits],
          resource_reservations: params[:resource_reservations],
          update_config: params[:update_config],
          rollback_config: params[:rollback_config]
        }.compact

        service = manager.create_service(service_params)
        { success: true, service: service.service_summary, message: "Service created" }
      end

      def update_service(params)
        cluster = resolve_cluster(params[:cluster_id])
        service = resolve_service(cluster, params[:service_id])
        manager = Devops::Docker::ServiceManager.new(cluster: cluster, user: user)

        # Build update spec from current service + changes
        docker_service = Devops::Docker::ApiClient.new(cluster).service_inspect(service.docker_service_id)
        spec = docker_service["Spec"] || {}

        # Apply changes
        if params[:image].present?
          spec["TaskTemplate"] ||= {}
          spec["TaskTemplate"]["ContainerSpec"] ||= {}
          spec["TaskTemplate"]["ContainerSpec"]["Image"] = params[:image]
        end

        if params[:environment].present?
          spec["TaskTemplate"] ||= {}
          spec["TaskTemplate"]["ContainerSpec"] ||= {}
          spec["TaskTemplate"]["ContainerSpec"]["Env"] = Array(params[:environment])
        end

        if params[:constraints].present?
          spec["TaskTemplate"] ||= {}
          spec["TaskTemplate"]["Placement"] = { "Constraints" => Array(params[:constraints]) }
        end

        spec["Labels"] = params[:labels].to_h if params[:labels].present?

        if params[:resource_limits].present?
          spec["TaskTemplate"] ||= {}
          spec["TaskTemplate"]["Resources"] ||= {}
          spec["TaskTemplate"]["Resources"]["Limits"] = params[:resource_limits].to_h
        end

        result = manager.update_service(service, spec)
        result
      end

      def scale_service(params)
        cluster = resolve_cluster(params[:cluster_id])
        service = resolve_service(cluster, params[:service_id])
        manager = Devops::Docker::ServiceManager.new(cluster: cluster, user: user)

        result = manager.scale_service(service, params[:replicas])
        result
      end

      def rollback_service(params)
        cluster = resolve_cluster(params[:cluster_id])
        service = resolve_service(cluster, params[:service_id])
        manager = Devops::Docker::ServiceManager.new(cluster: cluster, user: user)

        result = manager.rollback_service(service)
        result
      end

      def remove_service(params)
        cluster = resolve_cluster(params[:cluster_id])
        service = resolve_service(cluster, params[:service_id])
        manager = Devops::Docker::ServiceManager.new(cluster: cluster, user: user)

        service_name = service.service_name
        result = manager.remove_service(service)
        result.merge(service_name: service_name)
      end

      def service_logs(params)
        cluster = resolve_cluster(params[:cluster_id])
        service = resolve_service(cluster, params[:service_id])
        manager = Devops::Docker::ServiceManager.new(cluster: cluster, user: user)

        opts = { tail: params[:tail] || "100" }
        entries = manager.service_logs(service, opts)

        {
          success: true,
          service: service.service_name,
          log_entries: entries.is_a?(Array) ? entries.first(500) : [],
          count: entries.is_a?(Array) ? entries.size : 0
        }
      end

      def service_tasks(params)
        cluster = resolve_cluster(params[:cluster_id])
        service = resolve_service(cluster, params[:service_id])
        manager = Devops::Docker::ServiceManager.new(cluster: cluster, user: user)

        tasks = manager.list_tasks(service)

        if tasks.is_a?(Array)
          {
            success: true,
            service: service.service_name,
            tasks: tasks.map do |t|
              {
                id: t["ID"],
                status: t.dig("Status", "State"),
                desired_state: t["DesiredState"],
                node_id: t["NodeID"],
                message: t.dig("Status", "Message"),
                error: t.dig("Status", "Err"),
                timestamp: t.dig("Status", "Timestamp"),
                container_id: t.dig("Status", "ContainerStatus", "ContainerID")&.first(12)
              }
            end,
            count: tasks.size
          }
        else
          tasks
        end
      end
    end
  end
end
