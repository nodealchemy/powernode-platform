# frozen_string_literal: true

module Ai
  module Tools
    class DockerContainerTool < BaseTool
      include Concerns::DockerContextResolvable

      REQUIRED_PERMISSION = "docker.containers.read"

      def self.definition
        {
          name: "docker_container_management",
          description: "Manage Docker containers: list, inspect, create, start, stop, restart, remove, logs, stats, exec",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            host_id: { type: "string", required: false, description: "Docker host ID, slug, or name (auto-selects if only one)" },
            container_id: { type: "string", required: false, description: "Container UUID, docker_container_id, or name" },
            name: { type: "string", required: false, description: "Container name (for create)" },
            image: { type: "string", required: false, description: "Image name (for create)" },
            command: { type: "array", required: false, description: "Command to execute (for exec)" },
            timeout: { type: "integer", required: false, description: "Timeout in seconds (for stop/restart)" },
            force: { type: "boolean", required: false, description: "Force removal (for remove)" },
            tail: { type: "string", required: false, description: "Number of log lines to return (for logs, default: 100)" },
            since: { type: "string", required: false, description: "Show logs since timestamp (for logs)" },
            working_dir: { type: "string", required: false, description: "Working directory (for exec)" },
            env: { type: "array", required: false, description: "Environment variables (for exec/create)" },
            params: { type: "object", required: false, description: "Additional container parameters (for create)" }
          }
        }
      end

      def self.action_definitions
        {
          "docker_list_containers" => {
            description: "List all containers on a Docker host with their status, image, and ports",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name (auto-selects if only one)" }
            }
          },
          "docker_get_container" => {
            description: "Get detailed information about a specific container",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              container_id: { type: "string", required: true, description: "Container UUID, docker_container_id, or name" }
            }
          },
          "docker_create_container" => {
            description: "Create a new Docker container on a host",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              name: { type: "string", required: true, description: "Container name" },
              image: { type: "string", required: true, description: "Docker image to use" },
              env: { type: "array", required: false, description: "Environment variables as KEY=VALUE strings" },
              params: { type: "object", required: false, description: "Additional Docker container parameters" }
            }
          },
          "docker_start_container" => {
            description: "Start a stopped container",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              container_id: { type: "string", required: true, description: "Container UUID, docker_container_id, or name" }
            }
          },
          "docker_stop_container" => {
            description: "Stop a running container",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              container_id: { type: "string", required: true, description: "Container UUID, docker_container_id, or name" },
              timeout: { type: "integer", required: false, description: "Seconds to wait before killing (default: 10)" }
            }
          },
          "docker_restart_container" => {
            description: "Restart a container",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              container_id: { type: "string", required: true, description: "Container UUID, docker_container_id, or name" },
              timeout: { type: "integer", required: false, description: "Seconds to wait before killing (default: 10)" }
            }
          },
          "docker_remove_container" => {
            description: "Remove a container (must be stopped unless force is true)",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              container_id: { type: "string", required: true, description: "Container UUID, docker_container_id, or name" },
              force: { type: "boolean", required: false, description: "Force removal of running container" }
            }
          },
          "docker_container_logs" => {
            description: "Retrieve logs from a container",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              container_id: { type: "string", required: true, description: "Container UUID, docker_container_id, or name" },
              tail: { type: "string", required: false, description: "Number of lines from the end (default: 100)" },
              since: { type: "string", required: false, description: "Show logs since timestamp or duration (e.g. '10m')" }
            }
          },
          "docker_container_stats" => {
            description: "Get real-time resource usage statistics for a container (CPU, memory, network I/O)",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              container_id: { type: "string", required: true, description: "Container UUID, docker_container_id, or name" }
            }
          },
          "docker_container_exec" => {
            description: "Execute a command inside a running container (non-interactive, 100KB output limit)",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              container_id: { type: "string", required: true, description: "Container UUID, docker_container_id, or name" },
              command: { type: "array", required: true, description: "Command and arguments, e.g. ['ls', '-la', '/app']" },
              working_dir: { type: "string", required: false, description: "Working directory inside the container" },
              env: { type: "array", required: false, description: "Additional environment variables as KEY=VALUE" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "docker_list_containers" then list_containers(params)
        when "docker_get_container" then get_container(params)
        when "docker_create_container" then create_container(params)
        when "docker_start_container" then start_container(params)
        when "docker_stop_container" then stop_container(params)
        when "docker_restart_container" then restart_container(params)
        when "docker_remove_container" then remove_container(params)
        when "docker_container_logs" then container_logs(params)
        when "docker_container_stats" then container_stats(params)
        when "docker_container_exec" then container_exec(params)
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

      def list_containers(params)
        host = resolve_host(params[:host_id])
        containers = host.docker_containers.order(state: :asc, name: :asc)

        {
          success: true,
          host: { id: host.id, name: host.name },
          containers: containers.map do |c|
            {
              id: c.id,
              docker_container_id: c.docker_container_id&.first(12),
              name: c.name,
              image: c.image,
              state: c.state,
              status_text: c.status_text,
              ports: c.ports,
              labels: c.labels,
              last_seen_at: c.last_seen_at
            }
          end,
          count: containers.size
        }
      end

      def get_container(params)
        host = resolve_host(params[:host_id])
        container = resolve_container(host, params[:container_id])

        {
          success: true,
          container: {
            id: container.id,
            docker_container_id: container.docker_container_id,
            name: container.name,
            image: container.image,
            image_id: container.image_id,
            state: container.state,
            status_text: container.status_text,
            command: container.command,
            ports: container.ports,
            mounts: container.mounts,
            networks: container.networks,
            labels: container.labels,
            started_at: container.started_at,
            finished_at: container.finished_at,
            restart_count: container.restart_count,
            last_seen_at: container.last_seen_at,
            created_at: container.created_at
          }
        }
      end

      def create_container(params)
        host = resolve_host(params[:host_id])
        manager = Devops::Docker::ContainerManager.new(host: host, user: user)

        create_params = (params[:params] || {}).symbolize_keys
        create_params[:Env] = params[:env] if params[:env].present?

        result = manager.create_container(name: params[:name], image: params[:image], params: create_params)
        { success: true, container_id: result["Id"], message: "Container created" }
      end

      def start_container(params)
        host = resolve_host(params[:host_id])
        container = resolve_container(host, params[:container_id])
        manager = Devops::Docker::ContainerManager.new(host: host, user: user)

        manager.start_container(container)
        { success: true, container: container.name, state: container.reload.state }
      end

      def stop_container(params)
        host = resolve_host(params[:host_id])
        container = resolve_container(host, params[:container_id])
        manager = Devops::Docker::ContainerManager.new(host: host, user: user)

        timeout = (params[:timeout] || 10).to_i
        manager.stop_container(container, timeout: timeout)
        { success: true, container: container.name, state: container.reload.state }
      end

      def restart_container(params)
        host = resolve_host(params[:host_id])
        container = resolve_container(host, params[:container_id])
        manager = Devops::Docker::ContainerManager.new(host: host, user: user)

        timeout = (params[:timeout] || 10).to_i
        manager.restart_container(container, timeout: timeout)
        { success: true, container: container.name, state: container.reload.state }
      end

      def remove_container(params)
        host = resolve_host(params[:host_id])
        container = resolve_container(host, params[:container_id])
        manager = Devops::Docker::ContainerManager.new(host: host, user: user)

        force = params[:force] == true
        container_name = container.name
        manager.remove_container(container, force: force)
        { success: true, container: container_name, message: "Container removed" }
      end

      def container_logs(params)
        host = resolve_host(params[:host_id])
        container = resolve_container(host, params[:container_id])
        manager = Devops::Docker::ContainerManager.new(host: host, user: user)

        opts = { tail: params[:tail] || "100" }
        opts[:since] = params[:since] if params[:since].present?

        entries = manager.container_logs(container, opts)
        {
          success: true,
          container: container.name,
          log_entries: entries.is_a?(Array) ? entries.first(500) : [],
          count: entries.is_a?(Array) ? entries.size : 0
        }
      end

      def container_stats(params)
        host = resolve_host(params[:host_id])
        container = resolve_container(host, params[:container_id])
        manager = Devops::Docker::ContainerManager.new(host: host, user: user)

        stats = manager.container_stats(container)
        {
          success: true,
          container: container.name,
          stats: stats
        }
      end

      def container_exec(params)
        host = resolve_host(params[:host_id])
        container = resolve_container(host, params[:container_id])
        manager = Devops::Docker::ContainerManager.new(host: host, user: user)

        opts = {}
        opts[:working_dir] = params[:working_dir] if params[:working_dir].present?
        opts[:env] = params[:env] if params[:env].present?

        result = manager.exec_command(container, params[:command], opts)
        {
          success: true,
          container: container.name,
          output: result[:output],
          exit_code: result[:exit_code]
        }
      end
    end
  end
end
