# frozen_string_literal: true

require "faraday"
require "openssl"

module Docker
  class HostSyncJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 2

    DOCKER_API_VERSION = "v1.45"

    def execute
      log_info "Starting Docker host sync"

      hosts = fetch_syncable_hosts
      log_info "Found syncable Docker hosts", count: hosts.size

      synced = 0
      failed = 0

      hosts.each do |host|
        sync_host(host)
        synced += 1
      rescue StandardError => e
        log_error "Failed to sync Docker host", e, host_id: host["id"], name: host["name"]
        failed += 1
      end

      log_info "Docker host sync completed", synced: synced, failed: failed
    end

    private

    def fetch_syncable_hosts
      response = api_client.get("/api/v1/internal/docker/hosts", auto_sync: true)
      response.dig("data", "hosts") || []
    end

    def sync_host(host)
      log_info "Syncing Docker host", host_id: host["id"], name: host["name"]

      connection = fetch_connection_details(host["id"])
      docker = build_docker_client(connection)

      containers = fetch_docker_containers(docker)
      images = fetch_docker_images(docker)

      api_client.post("/api/v1/internal/docker/hosts/#{host['id']}/sync_results", {
        containers: containers,
        images: images,
        synced_at: Time.current.iso8601
      })

      log_info "Docker host synced", host_id: host["id"], containers: containers.size, images: images.size
    end

    def fetch_connection_details(host_id)
      response = api_client.get("/api/v1/internal/docker/hosts/#{host_id}/connection")
      response.dig("data", "connection")
    end

    def build_docker_client(connection)
      ssl_options = {}

      if connection["tls_enabled"]
        ssl_options[:client_cert] = OpenSSL::X509::Certificate.new(connection["client_cert"])
        ssl_options[:client_key] = OpenSSL::PKey::RSA.new(connection["client_key"])
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

    def fetch_docker_containers(docker)
      response = docker.get("/containers/json?all=true")

      unless response.success?
        raise "Docker API error fetching containers: #{response.status} - #{response.body}"
      end

      raw = JSON.parse(response.body)

      raw.map do |c|
        {
          docker_container_id: c["Id"],
          name: (c["Names"]&.first || "unknown").sub(/\A\//, ""),
          image: c["Image"],
          image_id: c["ImageID"],
          state: c["State"],
          status_text: c["Status"],
          ports: (c["Ports"] || []).map { |p| { ip: p["IP"], private_port: p["PrivatePort"], public_port: p["PublicPort"], type: p["Type"] } },
          mounts: c["Mounts"] || [],
          networks: c.dig("NetworkSettings", "Networks") || {},
          labels: c["Labels"] || {},
          command: c["Command"]
        }
      end
    end

    def fetch_docker_images(docker)
      response = docker.get("/images/json")

      unless response.success?
        raise "Docker API error fetching images: #{response.status} - #{response.body}"
      end

      raw = JSON.parse(response.body)

      raw.map do |i|
        {
          docker_image_id: i["Id"],
          repo_tags: i["RepoTags"] || [],
          repo_digests: i["RepoDigests"] || [],
          size_bytes: i["Size"],
          virtual_size: i["VirtualSize"],
          container_count: i["Containers"] || 0,
          labels: i["Labels"] || {},
          docker_created_at: i["Created"]
        }
      end
    end
  end
end
