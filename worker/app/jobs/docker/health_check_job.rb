# frozen_string_literal: true

require "faraday"
require "openssl"

module Docker
  class HealthCheckJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 2

    def execute
      log_info "Starting Docker host health checks"

      hosts = fetch_syncable_hosts
      log_info "Found Docker hosts for health check", count: hosts.size

      checked = 0
      failed = 0

      hosts.each do |host|
        check_host_health(host)
        checked += 1
      rescue StandardError => e
        log_error "Failed to check Docker host health", e, host_id: host["id"]
        report_health_failure(host, e.message)
        failed += 1
      end

      log_info "Docker host health checks completed", checked: checked, failed: failed
    end

    private

    def fetch_syncable_hosts
      response = api_client.get("/api/v1/internal/docker/hosts", auto_sync: true)
      response.dig("data", "hosts") || []
    end

    def check_host_health(host)
      connection = fetch_connection_details(host["id"])
      docker = build_docker_client(connection)

      response = docker.get("/_ping")
      alerts = []

      if response.success?
        info_response = docker.get("/v1.45/info")
        if info_response.success?
          info = JSON.parse(info_response.body)

          if info["MemTotal"] && info["MemoryLimit"]
            mem_used = info["MemTotal"] - (info["MemFree"] || 0)
            mem_pct = (mem_used.to_f / info["MemTotal"] * 100).round(1)
            if mem_pct > 90
              alerts << { type: "high_memory", severity: "warning", source_type: "host", source_name: host["name"], message: "Memory usage at #{mem_pct}%", metadata: { memory_percent: mem_pct } }
            end
          end
        end

        report_health_success(host, alerts)
      else
        report_health_failure(host, "Ping failed with status #{response.status}")
      end
    end

    def fetch_connection_details(host_id)
      response = api_client.get("/api/v1/internal/docker/hosts/#{host_id}/connection")
      response.dig("data", "connection")
    end

    def build_docker_client(connection)
      scheme = connection["tls_enabled"] ? "https" : "http"
      base_url = "#{scheme}://#{connection['host']}:#{connection['port']}"

      Faraday.new(url: base_url) do |f|
        if connection["tls_enabled"]
          f.ssl.client_cert = OpenSSL::X509::Certificate.new(connection["client_cert"])
          f.ssl.client_key = OpenSSL::PKey::RSA.new(connection["client_key"])
          f.ssl.verify = connection.fetch("tls_verify", true)
        end
        f.options.timeout = 10
        f.options.open_timeout = 5
        f.adapter Faraday.default_adapter
      end
    end

    def report_health_success(host, alerts = [])
      api_client.post("/api/v1/internal/docker/hosts/#{host['id']}/health_results", {
        status: "healthy",
        alerts: alerts
      })
    end

    def report_health_failure(host, error_message)
      api_client.post("/api/v1/internal/docker/hosts/#{host['id']}/health_results", {
        status: "unhealthy",
        alerts: [
          { type: "connectivity", severity: "error", source_type: "host", source_name: host["name"], message: "Health check failed: #{error_message}" }
        ]
      })
    end
  end
end
