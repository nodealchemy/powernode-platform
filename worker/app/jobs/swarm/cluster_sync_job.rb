# frozen_string_literal: true

require "faraday"
require "openssl"

module Swarm
  # Syncs Docker Swarm cluster state (nodes, services) from all auto-syncable clusters
  # Queue: devops_default
  # Retry: 2
  class ClusterSyncJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 2

    DOCKER_API_VERSION = "v1.41"

    # Sync all auto-syncable clusters
    def execute
      log_info "Starting Swarm cluster sync"

      clusters = fetch_syncable_clusters
      log_info "Found syncable clusters", count: clusters.size

      synced = 0
      failed = 0

      clusters.each do |cluster|
        sync_cluster(cluster)
        synced += 1
      rescue StandardError => e
        log_error "Failed to sync cluster", e, cluster_id: cluster["id"], name: cluster["name"]
        failed += 1
      end

      log_info "Swarm cluster sync completed", synced: synced, failed: failed
    end

    private

    def fetch_syncable_clusters
      response = api_client.get("/api/v1/internal/devops/swarm/clusters", auto_sync: true)
      response.dig("data", "clusters") || []
    end

    def sync_cluster(cluster)
      log_info "Syncing cluster", cluster_id: cluster["id"], name: cluster["name"]

      # Get connection details (host, port, TLS certs)
      connection = fetch_connection_details(cluster["id"])
      docker = build_docker_client(connection)

      # Fetch nodes, services, and running task counts from Docker API
      nodes = fetch_docker_nodes(docker)
      running_counts = fetch_running_task_counts(docker)
      services = fetch_docker_services(docker, running_counts)

      # Push results back to backend
      api_client.post("/api/v1/internal/devops/swarm/clusters/#{cluster['id']}/sync_results", {
        nodes: nodes,
        services: services,
        synced_at: Time.current.iso8601
      })

      log_info "Cluster synced", cluster_id: cluster["id"], nodes: nodes.size, services: services.size
    end

    def fetch_connection_details(cluster_id)
      response = api_client.get("/api/v1/internal/devops/swarm/clusters/#{cluster_id}/connection")
      response.dig("data", "connection")
    end

    def build_docker_client(connection)
      ssl_options = {}

      if connection["tls_enabled"]
        ssl_options[:client_cert] = OpenSSL::X509::Certificate.new(connection["client_cert"])
        ssl_options[:client_key] = OpenSSL::PKey::RSA.new(connection["client_key"])
        ssl_options[:ca_file] = nil # Will use ca_cert string instead
        ssl_options[:verify] = connection.fetch("tls_verify", true)
      end

      scheme = connection["tls_enabled"] ? "https" : "http"
      base_url = "#{scheme}://#{connection['host']}:#{connection['port']}/#{DOCKER_API_VERSION}"

      Faraday.new(url: base_url) do |f|
        if connection["tls_enabled"]
          f.ssl.client_cert = ssl_options[:client_cert]
          f.ssl.client_key = ssl_options[:client_key]
          f.ssl.ca_file = connection["ca_cert_path"] if connection["ca_cert_path"]
          f.ssl.verify = ssl_options[:verify]
        end
        f.options.timeout = 30
        f.options.open_timeout = 10
        f.adapter Faraday.default_adapter
      end
    end

    def fetch_docker_nodes(docker)
      response = docker.get("/nodes")

      unless response.success?
        raise "Docker API error fetching nodes: #{response.status} - #{response.body}"
      end

      raw_nodes = JSON.parse(response.body)

      raw_nodes.map do |node|
        nano_cpus = node.dig("Description", "Resources", "NanoCPUs")
        {
          docker_node_id: node["ID"],
          hostname: node.dig("Description", "Hostname"),
          role: node.dig("Spec", "Role"),
          availability: node.dig("Spec", "Availability"),
          status: node.dig("Status", "State"),
          manager_status: node.dig("ManagerStatus", "Reachability"),
          ip_address: node.dig("Status", "Addr"),
          engine_version: node.dig("Description", "Engine", "EngineVersion"),
          os: node.dig("Description", "Platform", "OS"),
          architecture: node.dig("Description", "Platform", "Architecture"),
          memory_bytes: node.dig("Description", "Resources", "MemoryBytes"),
          cpu_count: nano_cpus ? nano_cpus / 1_000_000_000 : nil,
          labels: node.dig("Spec", "Labels") || {},
          leader: node.dig("ManagerStatus", "Leader") || false
        }
      end
    end

    def fetch_docker_services(docker, running_counts = {})
      response = docker.get("/services")

      unless response.success?
        raise "Docker API error fetching services: #{response.status} - #{response.body}"
      end

      raw_services = JSON.parse(response.body)

      raw_services.map do |svc|
        spec = svc["Spec"] || {}
        task_template = spec["TaskTemplate"] || {}
        {
          docker_service_id: svc["ID"],
          service_name: spec["Name"],
          image: task_template.dig("ContainerSpec", "Image"),
          mode: spec.dig("Mode", "Replicated") ? "replicated" : "global",
          desired_replicas: spec.dig("Mode", "Replicated", "Replicas") || 1,
          running_replicas: running_counts[svc["ID"]] || 0,
          ports: extract_ports(svc),
          constraints: task_template.dig("Placement", "Constraints") || [],
          resource_limits: task_template.dig("Resources", "Limits") || {},
          resource_reservations: task_template.dig("Resources", "Reservations") || {},
          update_config: spec["UpdateConfig"] || {},
          rollback_config: spec["RollbackConfig"] || {},
          labels: spec["Labels"] || {},
          environment: task_template.dig("ContainerSpec", "Env") || [],
          version: svc.dig("Version", "Index"),
          stack_namespace: spec.dig("Labels", "com.docker.stack.namespace"),
          created_at: svc["CreatedAt"],
          updated_at: svc["UpdatedAt"]
        }
      end
    end

    def fetch_running_task_counts(docker)
      response = docker.get("/tasks", filters: { "desired-state" => ["running"] }.to_json)

      unless response.success?
        log_warn "Failed to fetch tasks for running counts: #{response.status}"
        return {}
      end

      raw_tasks = JSON.parse(response.body)

      raw_tasks.each_with_object(Hash.new(0)) do |task, counts|
        next unless task.dig("Status", "State") == "running"

        counts[task["ServiceID"]] += 1
      end
    end

    def extract_ports(service)
      ports = service.dig("Endpoint", "Ports") || []
      ports.map do |port|
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
