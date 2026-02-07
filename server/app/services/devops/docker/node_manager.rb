# frozen_string_literal: true

module Devops
  module Docker
    class NodeManager
      def initialize(cluster:)
        @cluster = cluster
        @client = ApiClient.new(cluster)
      end

      def list
        docker_nodes = @client.node_list
        sync_nodes(docker_nodes)
        docker_nodes
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to list nodes for cluster #{@cluster.name}: #{e.message}")
        raise
      end

      def inspect_node(node_id)
        @client.node_inspect(node_id)
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to inspect node #{node_id}: #{e.message}")
        raise
      end

      def promote(node)
        update_node_role(node, "manager")
      end

      def demote(node)
        update_node_role(node, "worker")
      end

      def drain(node)
        update_node_availability(node, "drain")
      end

      def activate(node)
        update_node_availability(node, "active")
      end

      def remove(node)
        @client.node_delete(node.docker_node_id)
        node.destroy!
        Rails.logger.info("Removed node #{node.hostname} (#{node.docker_node_id}) from cluster #{@cluster.name}")
        { success: true }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to remove node #{node.docker_node_id}: #{e.message}")
        { success: false, error: e.message }
      end

      private

      def update_node_role(node, role)
        docker_node = @client.node_inspect(node.docker_node_id)
        version = docker_node.dig("Version", "Index")
        spec = docker_node["Spec"] || {}
        spec["Role"] = role

        @client.node_update(node.docker_node_id, version, spec)
        node.update!(role: role)

        Rails.logger.info("Updated node #{node.hostname} role to #{role}")
        { success: true, role: role }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to update node #{node.docker_node_id} role to #{role}: #{e.message}")
        { success: false, error: e.message }
      end

      def update_node_availability(node, availability)
        docker_node = @client.node_inspect(node.docker_node_id)
        version = docker_node.dig("Version", "Index")
        spec = docker_node["Spec"] || {}
        spec["Availability"] = availability

        @client.node_update(node.docker_node_id, version, spec)
        node.update!(availability: availability)

        Rails.logger.info("Updated node #{node.hostname} availability to #{availability}")
        { success: true, availability: availability }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to update node #{node.docker_node_id} availability to #{availability}: #{e.message}")
        { success: false, error: e.message }
      end

      def sync_nodes(docker_nodes)
        remote_ids = docker_nodes.map { |n| n["ID"] }
        @cluster.swarm_nodes.where.not(docker_node_id: remote_ids).destroy_all

        docker_nodes.each do |docker_node|
          node = @cluster.swarm_nodes.find_or_initialize_by(docker_node_id: docker_node["ID"])
          node.assign_attributes(
            hostname: docker_node.dig("Description", "Hostname") || "unknown",
            role: docker_node.dig("Spec", "Role") || "worker",
            availability: docker_node.dig("Spec", "Availability") || "active",
            status: docker_node.dig("Status", "State") || "unknown",
            manager_status: docker_node.dig("ManagerStatus", "Reachability"),
            ip_address: docker_node.dig("Status", "Addr"),
            engine_version: docker_node.dig("Description", "Engine", "EngineVersion"),
            os: docker_node.dig("Description", "Platform", "OS"),
            architecture: docker_node.dig("Description", "Platform", "Architecture"),
            memory_bytes: docker_node.dig("Description", "Resources", "MemoryBytes"),
            cpu_count: docker_node.dig("Description", "Resources", "NanoCPUs")&.then { |n| n / 1_000_000_000 },
            labels: docker_node.dig("Spec", "Labels") || {},
            last_seen_at: Time.current
          )
          node.save!
        end
      end
    end
  end
end
