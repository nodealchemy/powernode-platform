# frozen_string_literal: true

require "faraday"
require "openssl"

module Swarm
  # Health checks all connected Docker Swarm clusters
  # Queue: devops_default
  # Retry: 2
  class HealthCheckJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 2

    DOCKER_API_VERSION = "v1.41"
    NODE_HEALTHY_STATES = %w[ready].freeze
    TASK_RUNNING_STATES = %w[running].freeze

    # Check health of all connected clusters
    def execute
      log_info "Starting Swarm health checks"

      clusters = fetch_connected_clusters
      log_info "Found connected clusters", count: clusters.size

      checked = 0
      failed = 0

      clusters.each do |cluster|
        check_cluster_health(cluster)
        checked += 1
      rescue StandardError => e
        log_error "Health check failed for cluster", e, cluster_id: cluster["id"], name: cluster["name"]
        report_health_results(cluster["id"], {
          status: "unreachable",
          error: e.message,
          alerts: [{ severity: "critical", message: "Cluster unreachable: #{e.message}" }],
          checked_at: Time.current.iso8601
        })
        failed += 1
      end

      log_info "Swarm health checks completed", checked: checked, failed: failed
    end

    private

    def fetch_connected_clusters
      response = api_client.get("/api/v1/internal/swarm/clusters", status: "connected")
      response.dig("data", "clusters") || []
    end

    def check_cluster_health(cluster)
      log_info "Checking cluster health", cluster_id: cluster["id"], name: cluster["name"]

      connection = fetch_connection_details(cluster["id"])
      docker = build_docker_client(connection)

      alerts = []

      # Check Docker API reachability
      api_healthy = check_api_ping(docker)
      unless api_healthy
        alerts << { severity: "critical", message: "Docker API not responding" }
      end

      # Check node health
      node_alerts = check_node_health(docker)
      alerts.concat(node_alerts)

      # Check service health
      service_alerts = check_service_health(docker)
      alerts.concat(service_alerts)

      # Determine overall status
      status = if alerts.any? { |a| a[:severity] == "critical" }
                 "critical"
               elsif alerts.any? { |a| a[:severity] == "warning" }
                 "warning"
               else
                 "healthy"
               end

      report_health_results(cluster["id"], {
        status: status,
        alerts: alerts,
        checked_at: Time.current.iso8601
      })

      log_info "Cluster health check completed",
               cluster_id: cluster["id"],
               status: status,
               alerts: alerts.size
    end

    def fetch_connection_details(cluster_id)
      response = api_client.get("/api/v1/internal/swarm/clusters/#{cluster_id}/connection")
      response.dig("data", "connection")
    end

    def build_docker_client(connection)
      scheme = connection["tls_enabled"] ? "https" : "http"
      base_url = "#{scheme}://#{connection['host']}:#{connection['port']}/#{DOCKER_API_VERSION}"

      Faraday.new(url: base_url) do |f|
        if connection["tls_enabled"]
          f.ssl.client_cert = OpenSSL::X509::Certificate.new(connection["client_cert"])
          f.ssl.client_key = OpenSSL::PKey::RSA.new(connection["client_key"])
          f.ssl.ca_file = connection["ca_cert_path"] if connection["ca_cert_path"]
          f.ssl.verify = connection.fetch("tls_verify", true)
        end
        f.options.timeout = 15
        f.options.open_timeout = 5
        f.adapter Faraday.default_adapter
      end
    end

    def check_api_ping(docker)
      response = docker.get("/_ping")
      response.success?
    rescue StandardError
      false
    end

    def check_node_health(docker)
      alerts = []

      response = docker.get("/nodes")
      return [{ severity: "critical", message: "Cannot fetch node list" }] unless response.success?

      nodes = JSON.parse(response.body)
      total_nodes = nodes.size
      manager_nodes = nodes.select { |n| n.dig("Spec", "Role") == "manager" }
      down_nodes = nodes.reject { |n| NODE_HEALTHY_STATES.include?(n.dig("Status", "State")) }

      if down_nodes.any?
        down_names = down_nodes.map { |n| n.dig("Description", "Hostname") }.join(", ")
        alerts << { severity: "critical", message: "#{down_nodes.size}/#{total_nodes} nodes down: #{down_names}" }
      end

      if manager_nodes.size < 2 && total_nodes > 1
        alerts << { severity: "warning", message: "Only #{manager_nodes.size} manager node(s) — no HA" }
      end

      # Check for drain nodes
      drain_nodes = nodes.select { |n| n.dig("Spec", "Availability") == "drain" }
      if drain_nodes.any?
        drain_names = drain_nodes.map { |n| n.dig("Description", "Hostname") }.join(", ")
        alerts << { severity: "warning", message: "#{drain_nodes.size} node(s) in drain mode: #{drain_names}" }
      end

      alerts
    rescue StandardError => e
      [{ severity: "critical", message: "Failed to check node health: #{e.message}" }]
    end

    def check_service_health(docker)
      alerts = []

      response = docker.get("/services")
      return [{ severity: "warning", message: "Cannot fetch service list" }] unless response.success?

      services = JSON.parse(response.body)

      services.each do |svc|
        service_name = svc.dig("Spec", "Name")
        desired_replicas = svc.dig("Spec", "Mode", "Replicated", "Replicas")

        next unless desired_replicas # Skip global-mode services

        # Check running tasks for this service
        tasks_response = docker.get("/tasks", filters: { service: [svc["ID"]], "desired-state": ["running"] }.to_json)
        next unless tasks_response.success?

        tasks = JSON.parse(tasks_response.body)
        running_tasks = tasks.count { |t| TASK_RUNNING_STATES.include?(t.dig("Status", "State")) }

        if running_tasks < desired_replicas
          alerts << {
            severity: running_tasks.zero? ? "critical" : "warning",
            message: "Service '#{service_name}' has #{running_tasks}/#{desired_replicas} replicas running"
          }
        end
      end

      alerts
    rescue StandardError => e
      [{ severity: "warning", message: "Failed to check service health: #{e.message}" }]
    end

    def report_health_results(cluster_id, results)
      api_client.post("/api/v1/internal/swarm/clusters/#{cluster_id}/health_results", results)
    end
  end
end
