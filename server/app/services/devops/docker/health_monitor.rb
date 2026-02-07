# frozen_string_literal: true

module Devops
  module Docker
    class HealthMonitor
      def initialize(cluster:)
        @cluster = cluster
        @client = ApiClient.new(cluster)
        @alerts = []
      end

      def check_health
        connectivity = check_connectivity
        return connectivity_failure_result unless connectivity[:connected]

        node_health = check_node_health
        service_health = check_service_health

        @cluster.record_success!

        {
          success: true,
          cluster: @cluster.name,
          status: overall_status,
          connectivity: connectivity,
          nodes: node_health,
          services: service_health,
          alerts: @alerts,
          checked_at: Time.current
        }
      rescue ApiClient::ApiError => e
        @cluster.record_failure!
        Rails.logger.error("Health check failed for cluster #{@cluster.name}: #{e.message}")
        {
          success: false,
          cluster: @cluster.name,
          status: "error",
          error: e.message,
          checked_at: Time.current
        }
      end

      private

      def check_connectivity
        ping_result = @client.ping
        info_result = @client.info

        swarm_active = info_result.dig("Swarm", "LocalNodeState") == "active"
        unless swarm_active
          create_event("cluster_swarm_inactive", "warning", "cluster", @cluster.id,
            @cluster.name, "Swarm mode is not active on cluster")
        end

        {
          connected: true,
          swarm_active: swarm_active,
          api_version: info_result["ApiVersion"],
          server_version: info_result["ServerVersion"]
        }
      rescue ApiClient::ConnectionError => e
        create_event("cluster_unreachable", "critical", "cluster", @cluster.id,
          @cluster.name, "Cluster unreachable: #{e.message}")
        { connected: false, error: e.message }
      end

      def check_node_health
        nodes = @client.node_list

        total = nodes.size
        ready = 0
        down = 0
        managers = 0

        nodes.each do |node|
          status = node.dig("Status", "State")
          role = node.dig("Spec", "Role")
          hostname = node.dig("Description", "Hostname") || node["ID"]

          managers += 1 if role == "manager"

          case status
          when "ready"
            ready += 1
          when "down"
            down += 1
            severity = role == "manager" ? "critical" : "warning"
            create_event("node_down", severity, "node", node["ID"],
              hostname, "Node #{hostname} is down")
          else
            create_event("node_unhealthy", "warning", "node", node["ID"],
              hostname, "Node #{hostname} has status: #{status}")
          end

          # Check manager reachability
          if role == "manager"
            reachability = node.dig("ManagerStatus", "Reachability")
            if reachability && reachability != "reachable"
              create_event("manager_unreachable", "critical", "node", node["ID"],
                hostname, "Manager node #{hostname} is #{reachability}")
            end
          end
        end

        # Check manager quorum
        if managers > 0 && managers.even?
          create_event("manager_quorum_risk", "warning", "cluster", @cluster.id,
            @cluster.name, "Even number of managers (#{managers}) - risk of split-brain")
        end

        { total: total, ready: ready, down: down, managers: managers }
      end

      def check_service_health
        services = @client.service_list
        tasks = @client.task_list

        total = services.size
        healthy = 0
        degraded = 0
        failed = 0

        services.each do |service|
          service_id = service["ID"]
          service_name = service.dig("Spec", "Name") || service_id
          mode = service.dig("Spec", "Mode")

          desired_replicas = mode.dig("Replicated", "Replicas") if mode&.key?("Replicated")

          # Find running tasks for this service
          service_tasks = tasks.select { |t| t["ServiceID"] == service_id }
          running_tasks = service_tasks.select { |t| t.dig("Status", "State") == "running" }
          failed_tasks = service_tasks.select { |t| t.dig("Status", "State") == "failed" }

          if desired_replicas
            if running_tasks.size >= desired_replicas
              healthy += 1
            elsif running_tasks.size.zero?
              failed += 1
              create_event("service_down", "critical", "service", service_id,
                service_name, "Service #{service_name} has no running tasks (desired: #{desired_replicas})")
            else
              degraded += 1
              create_event("service_degraded", "warning", "service", service_id,
                service_name, "Service #{service_name} has #{running_tasks.size}/#{desired_replicas} running tasks")
            end
          else
            # Global service - just check if there are running tasks
            if running_tasks.any?
              healthy += 1
            else
              failed += 1
              create_event("service_down", "critical", "service", service_id,
                service_name, "Global service #{service_name} has no running tasks")
            end
          end

          # Check for repeated task failures
          recent_failures = failed_tasks.select do |t|
            timestamp = t.dig("Status", "Timestamp")
            timestamp && Time.parse(timestamp) > 10.minutes.ago
          rescue ArgumentError
            false
          end

          if recent_failures.size >= 3
            create_event("service_crash_loop", "error", "service", service_id,
              service_name, "Service #{service_name} has #{recent_failures.size} failed tasks in last 10 minutes")
          end
        end

        { total: total, healthy: healthy, degraded: degraded, failed: failed }
      end

      def create_event(event_type, severity, source_type, source_id, source_name, message)
        @alerts << { event_type: event_type, severity: severity, message: message }

        @cluster.swarm_events.create!(
          event_type: event_type,
          severity: severity,
          source_type: source_type,
          source_id: source_id.to_s,
          source_name: source_name,
          message: message
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to create swarm event: #{e.message}")
      end

      def overall_status
        return "critical" if @alerts.any? { |a| a[:severity] == "critical" }
        return "error" if @alerts.any? { |a| a[:severity] == "error" }
        return "warning" if @alerts.any? { |a| a[:severity] == "warning" }

        "healthy"
      end

      def connectivity_failure_result
        @cluster.record_failure!
        {
          success: false,
          cluster: @cluster.name,
          status: "unreachable",
          alerts: @alerts,
          checked_at: Time.current
        }
      end
    end
  end
end
