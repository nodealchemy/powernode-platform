# frozen_string_literal: true

module Ai
  module Tools
    class DockerNetworkVolumeTool < BaseTool
      include Concerns::DockerContextResolvable

      REQUIRED_PERMISSION = "swarm.networks.read"

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
          "docker_remove_network" => {
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
          "docker_remove_volume" => {
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
        case params[:action]
        when "docker_list_networks" then list_networks(params)
        when "docker_create_network" then create_network(params)
        when "docker_remove_network" then remove_network(params)
        when "docker_list_volumes" then list_volumes(params)
        when "docker_create_volume" then create_volume(params)
        when "docker_remove_volume" then remove_volume(params)
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
