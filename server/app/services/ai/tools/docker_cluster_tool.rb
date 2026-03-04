# frozen_string_literal: true

module Ai
  module Tools
    class DockerClusterTool < BaseTool
      include Concerns::DockerContextResolvable

      REQUIRED_PERMISSION = "swarm.clusters.read"

      def self.definition
        {
          name: "docker_cluster_management",
          description: "Manage Docker Swarm clusters: health checks, node management, secrets, and configs",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
            node_id: { type: "string", required: false, description: "Node UUID, docker_node_id, or hostname" },
            name: { type: "string", required: false, description: "Secret/config name" },
            data: { type: "string", required: false, description: "Secret/config data (base64 encoded for secrets)" },
            secret_id: { type: "string", required: false, description: "Docker secret ID" },
            config_id: { type: "string", required: false, description: "Docker config ID" },
            labels: { type: "object", required: false, description: "Labels for secret/config" }
          }
        }
      end

      def self.action_definitions
        {
          "docker_list_clusters" => {
            description: "List all Swarm clusters registered in the account with connection status",
            parameters: {}
          },
          "docker_get_cluster" => {
            description: "Get detailed information about a Swarm cluster including node/service counts",
            parameters: {
              cluster_id: { type: "string", required: true, description: "Swarm cluster ID, slug, or name" }
            }
          },
          "docker_cluster_health" => {
            description: "Run a comprehensive health check on a Swarm cluster: node status, service health, alerts",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name (auto-selects if only one)" }
            }
          },
          "docker_list_nodes" => {
            description: "List all nodes in a Swarm cluster with role, availability, and resource info",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" }
            }
          },
          "docker_node_promote" => {
            description: "Promote a worker node to manager role",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              node_id: { type: "string", required: true, description: "Node UUID, docker_node_id, or hostname" }
            }
          },
          "docker_node_demote" => {
            description: "Demote a manager node to worker role",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              node_id: { type: "string", required: true, description: "Node UUID, docker_node_id, or hostname" }
            }
          },
          "docker_node_drain" => {
            description: "Drain a node (stop scheduling tasks, migrate existing tasks to other nodes)",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              node_id: { type: "string", required: true, description: "Node UUID, docker_node_id, or hostname" }
            }
          },
          "docker_node_activate" => {
            description: "Activate a drained node (resume task scheduling)",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              node_id: { type: "string", required: true, description: "Node UUID, docker_node_id, or hostname" }
            }
          },
          "docker_list_secrets" => {
            description: "List all secrets in a Swarm cluster (metadata only, not secret data)",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" }
            }
          },
          "docker_create_secret" => {
            description: "Create a new secret in the Swarm cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              name: { type: "string", required: true, description: "Secret name" },
              data: { type: "string", required: true, description: "Secret data (will be base64 encoded)" },
              labels: { type: "object", required: false, description: "Secret labels" }
            }
          },
          "docker_remove_secret" => {
            description: "Remove a secret from the Swarm cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              secret_id: { type: "string", required: true, description: "Docker secret ID" }
            }
          },
          "docker_list_configs" => {
            description: "List all configs in a Swarm cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" }
            }
          },
          "docker_create_config" => {
            description: "Create a new config in the Swarm cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              name: { type: "string", required: true, description: "Config name" },
              data: { type: "string", required: true, description: "Config data (will be base64 encoded)" },
              labels: { type: "object", required: false, description: "Config labels" }
            }
          },
          "docker_remove_config" => {
            description: "Remove a config from the Swarm cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              config_id: { type: "string", required: true, description: "Docker config ID" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "docker_list_clusters" then list_clusters(params)
        when "docker_get_cluster" then get_cluster(params)
        when "docker_cluster_health" then cluster_health(params)
        when "docker_list_nodes" then list_nodes(params)
        when "docker_node_promote" then node_promote(params)
        when "docker_node_demote" then node_demote(params)
        when "docker_node_drain" then node_drain(params)
        when "docker_node_activate" then node_activate(params)
        when "docker_list_secrets" then list_secrets(params)
        when "docker_create_secret" then create_secret(params)
        when "docker_remove_secret" then remove_secret(params)
        when "docker_list_configs" then list_configs(params)
        when "docker_create_config" then create_config(params)
        when "docker_remove_config" then remove_config(params)
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

      # --- Cluster ---

      def list_clusters(_params)
        clusters = account.devops_swarm_clusters.order(:name)

        {
          success: true,
          clusters: clusters.map { |c| c.cluster_summary },
          count: clusters.size
        }
      end

      def get_cluster(params)
        cluster = resolve_cluster(params[:cluster_id])
        nodes = cluster.swarm_nodes.order(:hostname)

        {
          success: true,
          cluster: cluster.cluster_details,
          nodes_summary: {
            total: nodes.count,
            managers: nodes.managers.count,
            workers: nodes.workers.count,
            ready: nodes.ready.count
          }
        }
      end

      def cluster_health(params)
        cluster = resolve_cluster(params[:cluster_id])
        monitor = Devops::Docker::HealthMonitor.new(cluster: cluster)
        health = monitor.check_health

        { success: true }.merge(health)
      end

      # --- Nodes ---

      def list_nodes(params)
        cluster = resolve_cluster(params[:cluster_id])
        nodes = cluster.swarm_nodes.order(:role, :hostname)

        {
          success: true,
          cluster: { id: cluster.id, name: cluster.name },
          nodes: nodes.map { |n| n.node_summary },
          count: nodes.size
        }
      end

      def node_promote(params)
        cluster = resolve_cluster(params[:cluster_id])
        node = resolve_node(cluster, params[:node_id])
        manager = Devops::Docker::NodeManager.new(cluster: cluster)

        manager.promote(node)
      end

      def node_demote(params)
        cluster = resolve_cluster(params[:cluster_id])
        node = resolve_node(cluster, params[:node_id])
        manager = Devops::Docker::NodeManager.new(cluster: cluster)

        manager.demote(node)
      end

      def node_drain(params)
        cluster = resolve_cluster(params[:cluster_id])
        node = resolve_node(cluster, params[:node_id])
        manager = Devops::Docker::NodeManager.new(cluster: cluster)

        manager.drain(node)
      end

      def node_activate(params)
        cluster = resolve_cluster(params[:cluster_id])
        node = resolve_node(cluster, params[:node_id])
        manager = Devops::Docker::NodeManager.new(cluster: cluster)

        manager.activate(node)
      end

      # --- Secrets ---

      def list_secrets(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::SecretManager.new(cluster: cluster)

        secrets = manager.list
        { success: true, secrets: secrets, count: secrets.size }
      end

      def create_secret(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::SecretManager.new(cluster: cluster)

        spec = {
          "Name" => params[:name],
          "Data" => Base64.strict_encode64(params[:data]),
          "Labels" => params[:labels] || {}
        }

        manager.create(spec)
      end

      def remove_secret(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::SecretManager.new(cluster: cluster)

        manager.remove(params[:secret_id])
      end

      # --- Configs ---

      def list_configs(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::SecretManager.new(cluster: cluster)

        configs = manager.list_configs
        { success: true, configs: configs, count: configs.size }
      end

      def create_config(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::SecretManager.new(cluster: cluster)

        spec = {
          "Name" => params[:name],
          "Data" => Base64.strict_encode64(params[:data]),
          "Labels" => params[:labels] || {}
        }

        manager.create_config(spec)
      end

      def remove_config(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::SecretManager.new(cluster: cluster)

        manager.remove_config(params[:config_id])
      end
    end
  end
end
