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
        running_counts = fetch_running_task_counts(client)
        sync_stacks(cluster, services)
        sync_services(cluster, services, running_counts: running_counts)

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

      def adopt_stack(cluster, stack_name)
        client = ApiClient.new(cluster)
        stack_label = Devops::Docker::StackManager::STACK_LABEL
        managed_label = Devops::Docker::StackManager::MANAGED_LABEL

        docker_services = client.service_list
        stack_services = docker_services.select do |ds|
          ds.dig("Spec", "Labels", stack_label) == stack_name
        end

        return { success: false, error: "No Docker services found for stack '#{stack_name}'" } if stack_services.empty?

        # Tag each service with powernode.managed=true via Docker API
        tagged = 0
        stack_services.each do |ds|
          labels = ds.dig("Spec", "Labels") || {}
          next if labels[managed_label] == "true"

          spec = ds["Spec"].deep_dup
          spec["Labels"][managed_label] = "true"
          version = ds.dig("Version", "Index")
          client.service_update(ds["ID"], version, spec)
          tagged += 1
        end

        # Create or update the stack record
        stack = cluster.swarm_stacks.find_or_initialize_by(name: stack_name)
        stack.assign_attributes(
          source: "discovered",
          status: "deployed",
          service_count: stack_services.size,
          last_deployed_at: Time.current
        )
        stack.save!

        # Import the services with running replica counts
        running_counts = fetch_running_task_counts(client)
        stack_services.each do |ds|
          service = cluster.swarm_services.find_or_initialize_by(docker_service_id: ds["ID"])
          update_service_from_docker(service, ds, cluster, running_counts: running_counts)
        end

        Rails.logger.info("Adopted stack #{stack_name}: #{stack_services.size} services, #{tagged} newly tagged")
        { success: true, stack: stack, services: stack_services.size, tagged: tagged }
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to adopt stack #{stack_name}: #{e.message}")
        { success: false, error: e.message }
      end

      def import_services(cluster, docker_service_ids)
        client = ApiClient.new(cluster)
        docker_services = client.service_list
        running_counts = fetch_running_task_counts(client)
        imported = []

        docker_services.each do |docker_service|
          next unless docker_service_ids.include?(docker_service["ID"])
          next if cluster.swarm_services.exists?(docker_service_id: docker_service["ID"])

          service = cluster.swarm_services.new(docker_service_id: docker_service["ID"])
          update_service_from_docker(service, docker_service, cluster, running_counts: running_counts)
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

      def sync_stacks(cluster, docker_services)
        stack_label = Devops::Docker::StackManager::STACK_LABEL
        managed_label = Devops::Docker::StackManager::MANAGED_LABEL

        # Group managed services by stack namespace
        stack_groups = docker_services.each_with_object({}) do |ds, groups|
          labels = ds.dig("Spec", "Labels") || {}
          next unless labels[managed_label] == "true"

          stack_name = labels[stack_label]
          next unless stack_name.present?

          groups[stack_name] ||= 0
          groups[stack_name] += 1
        end

        # Create or update managed stacks
        stack_groups.each do |stack_name, svc_count|
          stack = cluster.swarm_stacks.find_or_initialize_by(name: stack_name)

          if stack.new_record?
            stack.assign_attributes(
              source: "discovered",
              status: "deployed",
              service_count: svc_count,
              last_deployed_at: Time.current
            )
          else
            stack.assign_attributes(
              status: "deployed",
              service_count: svc_count
            )
          end

          stack.save!
        end

        # Mark discovered stacks as removed if no longer found in Docker
        cluster.swarm_stacks.discovered.where.not(name: stack_groups.keys).where.not(status: "removed").update_all(status: "removed", service_count: 0)
      end

      def sync_services(cluster, docker_services, running_counts: {})
        managed_label = Devops::Docker::StackManager::MANAGED_LABEL
        remote_ids = docker_services.map { |s| s["ID"] }

        # Remove imported services that no longer exist in Docker
        cluster.swarm_services.where.not(docker_service_id: remote_ids).destroy_all

        docker_services.each do |docker_service|
          labels = docker_service.dig("Spec", "Labels") || {}

          if labels[managed_label] == "true"
            # Auto-import services tagged as Powernode-managed
            service = cluster.swarm_services.find_or_initialize_by(docker_service_id: docker_service["ID"])
            update_service_from_docker(service, docker_service, cluster, running_counts: running_counts)
          else
            # Unmanaged services: only update already-imported ones
            service = cluster.swarm_services.find_by(docker_service_id: docker_service["ID"])
            next unless service

            update_service_from_docker(service, docker_service, cluster, running_counts: running_counts)
          end
        end
      end

      def update_service_from_docker(service, docker_service, cluster, running_counts: {})
        spec = docker_service["Spec"] || {}
        task_template = spec["TaskTemplate"] || {}

        service.assign_attributes(
          service_name: spec["Name"] || "unknown",
          image: task_template.dig("ContainerSpec", "Image") || "unknown",
          mode: spec.dig("Mode", "Replicated") ? "replicated" : "global",
          desired_replicas: spec.dig("Mode", "Replicated", "Replicas") || 1,
          running_replicas: running_counts[docker_service["ID"]] || service.running_replicas,
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

      def fetch_running_task_counts(client)
        tasks = client.task_list("desired-state" => ["running"])

        tasks.each_with_object(Hash.new(0)) do |task, counts|
          next unless task.dig("Status", "State") == "running"

          counts[task["ServiceID"]] += 1
        end
      rescue ApiClient::ApiError => e
        Rails.logger.warn("Failed to fetch task counts: #{e.message}")
        {}
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
