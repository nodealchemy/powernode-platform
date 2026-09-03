# frozen_string_literal: true

module Ai
  module Tools
    class DockerHostTool < BaseTool
      include Concerns::DockerContextResolvable

      # SECURITY (IMP-48abfa2f9e74): this floor used to be "docker.hosts.read", a
      # name that appears ZERO times in config/permissions.rb. User#has_permission?
      # is an exact match on a role_permissions row plus a system.admin
      # short-circuit, so no row can ever exist for an undeclared name: every action
      # on this class was super-admin-only while tools/list advertised the whole
      # surface to everyone. b7598df74 created the devops.* family and moved the
      # REST twin onto it (Api::V1::Devops::Docker::HostsController); this class was
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
      #   docker_test_host stays at the READ floor on purpose. It is a
      #     connectivity probe — HostManager#test_connection pings, reads
      #     /info, then records connection bookkeeping
      #     (record_success!/record_failure!). No host mutation. b7598df74
      #     classified the identical hosts#test_connection action as read for
      #     exactly that reason; following the precedent, not the verb's name.
      #   docker_sync_host is manage: HostManager#sync_host rewrites the
      #     account's container and image rows from the daemon, and hosts#sync
      #     is gated devops.docker.manage.
      ACTION_PERMISSIONS = {
        "docker_sync_host" => "devops.docker.manage"
      }.freeze

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "docker_get_host", mutating: false
      declare_action "docker_list_hosts", mutating: false
      declare_action "docker_sync_host", mutating: true
      declare_action "docker_test_host", mutating: false

      def self.definition
        {
          name: "docker_host_management",
          description: "Manage Docker hosts: list, inspect, sync, and test connections",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" }
          }
        }
      end

      def self.action_definitions
        {
          "docker_list_hosts" => {
            description: "List all Docker hosts registered in the account with connection status and resource counts",
            parameters: {}
          },
          "docker_get_host" => {
            description: "Get detailed information about a Docker host including OS, resources, and Docker version",
            parameters: {
              host_id: { type: "string", required: true, description: "Docker host ID, slug, or name" }
            }
          },
          "docker_sync_host" => {
            description: "Synchronize a Docker host: fetch containers and images from the Docker daemon and update local records",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name (auto-selects if only one)" }
            }
          },
          "docker_test_host" => {
            description: "Test the connection to a Docker host and return system information",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name (auto-selects if only one)" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[DockerHostTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case params[:action]
        when "docker_list_hosts" then list_hosts(params)
        when "docker_get_host" then get_host(params)
        when "docker_sync_host" then sync_host(params)
        when "docker_test_host" then test_host(params)
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

      def list_hosts(_params)
        hosts = account.devops_docker_hosts.order(:name)

        {
          success: true,
          hosts: hosts.map { |h| h.host_summary },
          count: hosts.size
        }
      end

      def get_host(params)
        host = resolve_host(params[:host_id])

        {
          success: true,
          host: host.host_details,
          containers: {
            total: host.docker_containers.count,
            running: host.docker_containers.where(state: "running").count
          },
          images: {
            total: host.docker_images.count
          }
        }
      end

      def sync_host(params)
        host = resolve_host(params[:host_id])
        manager = Devops::Docker::HostManager.new(account: account)

        result = manager.sync_host(host)
        result.merge(host_name: host.name)
      end

      def test_host(params)
        host = resolve_host(params[:host_id])
        manager = Devops::Docker::HostManager.new(account: account)

        result = manager.test_connection(host)
        result.merge(host_name: host.name)
      end
    end
  end
end
