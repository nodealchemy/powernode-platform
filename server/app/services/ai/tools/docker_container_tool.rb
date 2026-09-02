# frozen_string_literal: true

module Ai
  module Tools
    class DockerContainerTool < BaseTool
      include Concerns::DockerContextResolvable

      # SECURITY (IMP-48abfa2f9e74): this floor used to be "docker.containers.read", a
      # name that appears ZERO times in config/permissions.rb. User#has_permission?
      # is an exact match on a role_permissions row plus a system.admin
      # short-circuit, so no row can ever exist for an undeclared name: every action
      # on this class was super-admin-only while tools/list advertised the whole
      # surface to everyone. b7598df74 created the devops.* family and moved the
      # REST twin onto it (Api::V1::Devops::Docker::ContainersController); this class was
      # missed by that sweep. Retargeted onto the same declared family, at the same
      # read/manage split the twin uses action for action.
      REQUIRED_PERMISSION = "devops.docker.read"

      # The floor retarget ALONE would be an escalation: pointing it at a read
      # permission newly grants every read holder the write/exec actions sitting
      # behind it. ACTION_PERMISSIONS raises each of those to the manage tier,
      # enforced against the action that RUNS — never against the invoked name,
      # since a user principal is not pinned to it
      # (McpPlatformToolRegistrar#action_pinned_to_name?) and can supply a sibling
      # :action. Actions ABSENT from this map sit at the floor deliberately:
      #
      #   docker_container_logs / docker_container_stats — the twin gates its
      #     logs and stats actions on devops.docker.read; both only read from
      #     the daemon.
      #   docker_container_exec is the one action with NO REST twin, and it is
      #     the sharpest verb here (arbitrary command execution inside a running
      #     container), so it takes the manage tier the mutating twins take.
      ACTION_PERMISSIONS = {
        "docker_create_container" => "devops.docker.manage",
        "docker_start_container" => "devops.docker.manage",
        "docker_stop_container" => "devops.docker.manage",
        "docker_restart_container" => "devops.docker.manage",
        "docker_delete_container" => "devops.docker.manage",
        "docker_container_exec" => "devops.docker.manage"
      }.freeze

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "docker_container_exec", mutating: true
      declare_action "docker_container_logs", mutating: false
      declare_action "docker_container_stats", mutating: false
      declare_action "docker_create_container", mutating: true
      declare_action "docker_delete_container", mutating: true
      declare_action "docker_get_container", mutating: false
      declare_action "docker_list_containers", mutating: false
      declare_action "docker_restart_container", mutating: true
      declare_action "docker_start_container", mutating: true
      declare_action "docker_stop_container", mutating: true

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
            description: "Create a new Docker container on a host. `runtime` sets the OCI runtime (e.g. 'runsc' for gVisor isolation, substrate L0) via HostConfig.Runtime — the runtime must be registered on the host's Docker daemon.",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              name: { type: "string", required: true, description: "Container name" },
              image: { type: "string", required: true, description: "Docker image to use" },
              env: { type: "array", required: false, description: "Environment variables as KEY=VALUE strings" },
              runtime: { type: "string", required: false, description: "OCI runtime for isolation (e.g. 'runsc' for gVisor) — sets HostConfig.Runtime" },
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
          "docker_delete_container" => {
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
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[DockerContainerTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case params[:action]
        when "docker_list_containers" then list_containers(params)
        when "docker_get_container" then get_container(params)
        when "docker_create_container" then create_container(params)
        when "docker_start_container" then start_container(params)
        when "docker_stop_container" then stop_container(params)
        when "docker_restart_container" then restart_container(params)
        when "docker_delete_container" then remove_container(params)
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

      # Falls back to the class floor for the read actions, which the registrar has
      # already enforced by the time this runs.
      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two explicit bypasses, matching the sibling tools' ladder (MemoryTool,
      # AgentAutonomyTool, SharedKnowledgeTool): in-process callers that opted in
      # with `internal: true`, and an mTLS node principal whose specific tool name
      # already cleared Mcp::Principal#may_invoke? and whose action the registrar
      # pinned to that same name. Never inferred from a nil user.
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the MCP
        # path coerces a permission answer, and a truthy non-boolean must not read
        # as a grant.
        user.has_permission?(required_perm_for(action)) == true
      end

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
        # L0 isolation consumption: route the container through an OCI runtime
        # (e.g. runsc for gVisor) via HostConfig.Runtime, without clobbering any
        # other HostConfig the caller supplied.
        if params[:runtime].present?
          host_config = (create_params[:HostConfig] ||= {})
          host_config[:Runtime] = params[:runtime].to_s
        end

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
