# frozen_string_literal: true

module Devops
  module Docker
    class SwarmManager
      def initialize(account:)
        @account = account
      end

      def register_cluster(params)
        cluster = @account.devops_swarm_clusters.new(params)

        unless cluster.save
          raise ActiveRecord::RecordInvalid, cluster
        end

        begin
          client = ApiClient.new(cluster)
          client.ping
          info_result = client.info

          swarm_info = client.swarm_inspect
          cluster.update!(
            swarm_id: swarm_info["ID"],
            status: "connected",
            node_count: info_result.dig("Swarm", "Nodes") || 0,
            service_count: info_result.dig("Swarm", "Managers") || 0,
            api_version: "v#{info_result["ApiVersion"] || "1.45"}",
            last_synced_at: Time.current
          )

          Rails.logger.info("Registered swarm cluster #{cluster.name} (#{cluster.swarm_id})")
        rescue ApiClient::ApiError => e
          cluster.update!(status: "error")
          Rails.logger.error("Failed to connect to cluster #{cluster.name}: #{e.message}")
        end

        cluster
      end

      def test_connection(cluster)
        client = ApiClient.new(cluster)
        ping_result = client.ping
        info_result = client.info

        cluster.record_success!

        {
          success: true,
          ping: ping_result,
          api_version: info_result["ApiVersion"],
          server_version: info_result["ServerVersion"],
          swarm_active: info_result.dig("Swarm", "LocalNodeState") == "active",
          nodes: info_result.dig("Swarm", "Nodes"),
          managers: info_result.dig("Swarm", "Managers"),
          os: info_result["OperatingSystem"],
          architecture: info_result["Architecture"],
          kernel_version: info_result["KernelVersion"]
        }
      rescue ApiClient::ConnectionError => e
        cluster.record_failure!
        { success: false, error: "Connection failed: #{e.message}" }
      rescue ApiClient::ApiError => e
        cluster.record_failure!
        { success: false, error: e.message }
      end

      def sync_cluster(cluster)
        client = ApiClient.new(cluster)

        nodes = client.node_list
        sync_nodes(cluster, nodes)

        services = client.service_list
        sync_services(cluster, services)

        cluster.update!(
          node_count: nodes.size,
          service_count: services.size,
          last_synced_at: Time.current,
          status: "connected",
          consecutive_failures: 0
        )

        Rails.logger.info("Synced cluster #{cluster.name}: #{nodes.size} nodes, #{services.size} services")
        { success: true, nodes: nodes.size, services: services.size }
      rescue ApiClient::ApiError => e
        cluster.record_failure!
        Rails.logger.error("Failed to sync cluster #{cluster.name}: #{e.message}")
        { success: false, error: e.message }
      end

      def remove_cluster(cluster)
        cluster.destroy!
        Rails.logger.info("Removed cluster #{cluster.name} from account #{@account.id}")
        { success: true }
      end

      def available_services(cluster)
        client = ApiClient.new(cluster)
        docker_services = client.service_list
        imported_ids = cluster.swarm_services.pluck(:docker_service_id)

        docker_services.map do |ds|
          spec = ds["Spec"] || {}
          task_template = spec["TaskTemplate"] || {}
          {
            docker_service_id: ds["ID"],
            service_name: spec["Name"] || "unknown",
            image: task_template.dig("ContainerSpec", "Image") || "unknown",
            mode: spec.dig("Mode", "Replicated") ? "replicated" : "global",
            desired_replicas: spec.dig("Mode", "Replicated", "Replicas") || 1,
            ports: extract_ports(spec["EndpointSpec"]),
            labels: spec["Labels"] || {},
            already_imported: imported_ids.include?(ds["ID"])
          }
        end
      end

      def import_services(cluster, docker_service_ids)
        client = ApiClient.new(cluster)
        docker_services = client.service_list
        imported = []

        docker_services.each do |docker_service|
          next unless docker_service_ids.include?(docker_service["ID"])
          next if cluster.swarm_services.exists?(docker_service_id: docker_service["ID"])

          service = cluster.swarm_services.new(docker_service_id: docker_service["ID"])
          update_service_from_docker(service, docker_service, cluster)
          imported << service
        end

        imported
      end

      private

      def sync_nodes(cluster, docker_nodes)
        existing_ids = cluster.swarm_nodes.pluck(:docker_node_id)
        remote_ids = docker_nodes.map { |n| n["ID"] }

        # Remove nodes that no longer exist
        cluster.swarm_nodes.where.not(docker_node_id: remote_ids).destroy_all

        docker_nodes.each do |docker_node|
          node = cluster.swarm_nodes.find_or_initialize_by(docker_node_id: docker_node["ID"])
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

      def sync_services(cluster, docker_services)
        remote_ids = docker_services.map { |s| s["ID"] }

        # Remove imported services that no longer exist in Docker
        cluster.swarm_services.where.not(docker_service_id: remote_ids).destroy_all

        # Only update already-imported services (do not create new ones)
        imported_ids = cluster.swarm_services.pluck(:docker_service_id)

        docker_services.each do |docker_service|
          next unless imported_ids.include?(docker_service["ID"])

          service = cluster.swarm_services.find_by(docker_service_id: docker_service["ID"])
          next unless service

          update_service_from_docker(service, docker_service, cluster)
        end
      end

      def update_service_from_docker(service, docker_service, cluster)
        spec = docker_service["Spec"] || {}
        task_template = spec["TaskTemplate"] || {}

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

        stack_name = spec.dig("Labels", "com.docker.stack.namespace")
        if stack_name.present?
          stack = cluster.swarm_stacks.find_by(name: stack_name)
          service.stack = stack if stack
        end

        service.save!
      end

      def extract_ports(endpoint_spec)
        return [] unless endpoint_spec

        (endpoint_spec["Ports"] || []).map do |port|
          {
            protocol: port["Protocol"],
            target_port: port["TargetPort"],
            published_port: port["PublishedPort"],
            publish_mode: port["PublishMode"]
          }
        end
      end
    end
  end
end
