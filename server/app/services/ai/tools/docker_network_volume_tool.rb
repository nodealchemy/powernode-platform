# frozen_string_literal: true

module Ai
  module Tools
    class DockerNetworkVolumeTool < BaseTool
      include Concerns::DockerContextResolvable

      # SECURITY (IMP-48abfa2f9e74): this floor used to be "swarm.networks.read", a
      # name that appears ZERO times in config/permissions.rb. User#has_permission?
      # is an exact match on a role_permissions row plus a system.admin
      # short-circuit, so no row can ever exist for an undeclared name: every action
      # on this class was super-admin-only while tools/list advertised the whole
      # surface to everyone. b7598df74 created the devops.* family and moved the
      # REST twin onto it (Api::V1::Devops::Swarm::{Networks,Volumes}Controller); this class was
      # missed by that sweep. Retargeted onto the same declared family, at the same
      # read/manage split the twin uses action for action.
      REQUIRED_PERMISSION = "devops.swarm.read"

      # The floor retarget ALONE would be an escalation: pointing it at a read
      # permission newly grants every read holder the write/exec actions sitting
      # behind it. ACTION_PERMISSIONS raises each of those to the manage tier,
      # enforced against the action that RUNS — never against the invoked name,
      # since a user principal is not pinned to it
      # (McpPlatformToolRegistrar#action_pinned_to_name?) and can supply a sibling
      # :action. Actions ABSENT from this map sit at the floor deliberately:
      #
      #   FAMILY CHOICE: networks and volumes exist in BOTH the plain-Docker and
      #   the Swarm worlds, and b7598df74 left two REST twins (devops/docker/*
      #   and devops/swarm/*). This class resolves its context with
      #   DockerContextResolvable#resolve_cluster (account.devops_swarm_clusters)
      #   and drives NetworkManager/VolumeManager with `cluster:`, so its twin is
      #   the SWARM pair — devops.swarm.*, not devops.docker.*.
      #
      #   docker_list_networks / docker_list_volumes stay at the read floor (twin
      #     index/show); create and delete take manage (twin create/destroy).
      ACTION_PERMISSIONS = {
        "docker_create_network" => "devops.swarm.manage",
        "docker_delete_network" => "devops.swarm.manage",
        "docker_create_volume" => "devops.swarm.manage",
        "docker_delete_volume" => "devops.swarm.manage"
      }.freeze

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "docker_create_network", mutating: true
      declare_action "docker_create_volume", mutating: true
      declare_action "docker_delete_network", mutating: true
      declare_action "docker_delete_volume", mutating: true
      declare_action "docker_list_networks", mutating: false
      declare_action "docker_list_volumes", mutating: false

      def self.definition
        {
          name: "docker_network_volume_management",
          description: "Manage Docker Swarm networks and volumes: list, create, remove",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
            name: { type: "string", required: false, description: "Network/volume name" },
            network_id: { type: "string", required: false, description: "Docker network ID" },
            volume_name: { type: "string", required: false, description: "Docker volume name" },
            driver: { type: "string", required: false, description: "Network/volume driver" },
            labels: { type: "object", required: false, description: "Labels" },
            attachable: { type: "boolean", required: false, description: "Whether network is attachable" },
            internal: { type: "boolean", required: false, description: "Whether network is internal" }
          }
        }
      end

      def self.action_definitions
        {
          "docker_list_networks" => {
            description: "List all networks on a Swarm cluster with driver, scope, and attachment info",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name (auto-selects if only one)" }
            }
          },
          "docker_create_network" => {
            description: "Create a new overlay network on the Swarm cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              name: { type: "string", required: true, description: "Network name" },
              driver: { type: "string", required: false, description: "Network driver (default: overlay)" },
              attachable: { type: "boolean", required: false, description: "Allow containers to attach (default: true)" },
              internal: { type: "boolean", required: false, description: "Internal network only (default: false)" },
              labels: { type: "object", required: false, description: "Network labels" }
            }
          },
          "docker_delete_network" => {
            description: "Remove a network from the Swarm cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              network_id: { type: "string", required: true, description: "Docker network ID or name" }
            }
          },
          "docker_list_volumes" => {
            description: "List all volumes on a Swarm cluster with driver and mount point info",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name (auto-selects if only one)" }
            }
          },
          "docker_create_volume" => {
            description: "Create a new volume on the Swarm cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              name: { type: "string", required: true, description: "Volume name" },
              driver: { type: "string", required: false, description: "Volume driver (default: local)" },
              labels: { type: "object", required: false, description: "Volume labels" }
            }
          },
          "docker_delete_volume" => {
            description: "Remove a volume from the Swarm cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              volume_name: { type: "string", required: true, description: "Docker volume name" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[DockerNetworkVolumeTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case params[:action]
        when "docker_list_networks" then list_networks(params)
        when "docker_create_network" then create_network(params)
        when "docker_delete_network" then remove_network(params)
        when "docker_list_volumes" then list_volumes(params)
        when "docker_create_volume" then create_volume(params)
        when "docker_delete_volume" then remove_volume(params)
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

      # --- Networks ---

      def list_networks(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::NetworkManager.new(cluster: cluster)

        networks = manager.list
        {
          success: true,
          cluster: { id: cluster.id, name: cluster.name },
          networks: networks,
          count: networks.size
        }
      end

      def create_network(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::NetworkManager.new(cluster: cluster)

        spec = {
          "Name" => params[:name],
          "Driver" => params[:driver] || "overlay",
          "Attachable" => params[:attachable] != false,
          "Internal" => params[:internal] == true,
          "Labels" => params[:labels] || {}
        }

        manager.create(spec)
      end

      def remove_network(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::NetworkManager.new(cluster: cluster)

        manager.remove(params[:network_id])
      end

      # --- Volumes ---

      def list_volumes(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::VolumeManager.new(cluster: cluster)

        volumes = manager.list
        {
          success: true,
          cluster: { id: cluster.id, name: cluster.name },
          volumes: volumes,
          count: volumes.size
        }
      end

      def create_volume(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::VolumeManager.new(cluster: cluster)

        spec = {
          "Name" => params[:name],
          "Driver" => params[:driver] || "local",
          "Labels" => params[:labels] || {}
        }

        manager.create(spec)
      end

      def remove_volume(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::VolumeManager.new(cluster: cluster)

        manager.remove(params[:volume_name])
      end
    end
  end
end
