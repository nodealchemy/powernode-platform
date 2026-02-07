# frozen_string_literal: true

require "faraday"
require "openssl"

module Swarm
  # Handles Docker Swarm service updates and rollbacks
  # Queue: devops_high
  # Retry: 1
  class ServiceUpdateJob < BaseJob
    sidekiq_options queue: "devops_high", retry: 1

    DOCKER_API_VERSION = "v1.41"
    CONVERGENCE_TIMEOUT = 300
    CONVERGENCE_POLL_INTERVAL = 5

    # Execute a service update or rollback
    # @param deployment_id [String] The deployment ID
    def execute(deployment_id)
      log_info "Starting service update", deployment_id: deployment_id

      deployment = fetch_deployment(deployment_id)
      update_deployment_status(deployment_id, "in_progress", started_at: Time.current.iso8601)

      connection = fetch_connection_details(deployment["cluster_id"])
      docker = build_docker_client(connection)

      action = deployment.fetch("action", "update")
      service_docker_id = deployment["service_docker_id"]

      case action
      when "update"
        perform_service_update(docker, deployment, service_docker_id)
      when "rollback"
        perform_service_rollback(docker, deployment, service_docker_id)
      else
        raise "Unknown action: #{action}"
      end

      # Monitor convergence
      converged = wait_for_convergence(docker, service_docker_id)

      status = converged ? "completed" : "partially_converged"
      update_deployment_status(deployment_id, status, {
        completed_at: Time.current.iso8601,
        result: { action: action, converged: converged }
      })

      log_info "Service update finished",
               deployment_id: deployment_id,
               action: action,
               status: status
    rescue StandardError => e
      log_error "Service update failed", e, deployment_id: deployment_id
      update_deployment_status(deployment_id, "failed", {
        completed_at: Time.current.iso8601,
        error_message: e.message
      })
      raise
    end

    private

    def fetch_deployment(deployment_id)
      response = api_client.get("/api/v1/internal/swarm/deployments/#{deployment_id}")
      response.dig("data", "deployment")
    end

    def update_deployment_status(deployment_id, status, extras = {})
      api_client.patch("/api/v1/internal/swarm/deployments/#{deployment_id}", {
        status: status
      }.merge(extras))
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
        f.options.timeout = 60
        f.options.open_timeout = 10
        f.adapter Faraday.default_adapter
      end
    end

    def perform_service_update(docker, deployment, service_docker_id)
      log_info "Performing service update", service_id: service_docker_id

      # Fetch current service spec
      current = fetch_service(docker, service_docker_id)
      version_index = current["Version"]["Index"]
      spec = current["Spec"]

      # Apply updates from deployment config
      updates = deployment.fetch("update_config", {})

      # Update image if specified
      if updates["image"]
        spec["TaskTemplate"]["ContainerSpec"]["Image"] = updates["image"]
      end

      # Update environment variables if specified
      if updates["environment"]
        spec["TaskTemplate"]["ContainerSpec"]["Env"] = updates["environment"].map { |k, v| "#{k}=#{v}" }
      end

      # Update replicas if specified
      if updates["replicas"] && spec.dig("Mode", "Replicated")
        spec["Mode"]["Replicated"]["Replicas"] = updates["replicas"].to_i
      end

      # Update resource limits if specified
      if updates["resources"]
        spec["TaskTemplate"]["Resources"] ||= {}
        if updates["resources"]["limits"]
          spec["TaskTemplate"]["Resources"]["Limits"] = updates["resources"]["limits"]
        end
      end

      # Apply update policy
      if updates["update_policy"]
        spec["UpdateConfig"] = {
          "Parallelism" => updates["update_policy"].fetch("parallelism", 1).to_i,
          "Delay" => (updates["update_policy"].fetch("delay_seconds", 10).to_i * 1_000_000_000),
          "FailureAction" => updates["update_policy"].fetch("failure_action", "rollback"),
          "Order" => updates["update_policy"].fetch("order", "stop-first")
        }
      end

      # Execute the update
      response = docker.post("/services/#{service_docker_id}/update?version=#{version_index}") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = spec.to_json
      end

      unless response.success?
        raise "Service update failed: #{response.status} - #{response.body}"
      end

      log_info "Service update submitted", service_id: service_docker_id
    end

    def perform_service_rollback(docker, deployment, service_docker_id)
      log_info "Performing service rollback", service_id: service_docker_id

      # Fetch current service spec
      current = fetch_service(docker, service_docker_id)
      version_index = current["Version"]["Index"]

      # Use PreviousSpec for rollback
      previous_spec = current["PreviousSpec"]
      raise "No previous spec available for rollback" unless previous_spec

      response = docker.post("/services/#{service_docker_id}/update?version=#{version_index}&rollback=previous") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = previous_spec.to_json
      end

      unless response.success?
        raise "Service rollback failed: #{response.status} - #{response.body}"
      end

      log_info "Service rollback submitted", service_id: service_docker_id
    end

    def fetch_service(docker, service_docker_id)
      response = docker.get("/services/#{service_docker_id}")

      unless response.success?
        raise "Failed to fetch service #{service_docker_id}: #{response.status} - #{response.body}"
      end

      JSON.parse(response.body)
    end

    def wait_for_convergence(docker, service_docker_id)
      deadline = Time.current + CONVERGENCE_TIMEOUT

      until Time.current > deadline
        service = fetch_service(docker, service_docker_id)
        desired = service.dig("Spec", "Mode", "Replicated", "Replicas") || 1

        # Check update status
        update_status = service.dig("UpdateStatus", "State")
        if update_status == "completed"
          log_info "Service update converged", service_id: service_docker_id
          return true
        elsif update_status == "rollback_completed"
          log_warn "Service update triggered automatic rollback", service_id: service_docker_id
          return false
        elsif update_status == "paused"
          log_warn "Service update paused", service_id: service_docker_id
          return false
        end

        # Check running tasks
        tasks_response = docker.get("/tasks", filters: { service: [service_docker_id], "desired-state": ["running"] }.to_json)
        if tasks_response.success?
          tasks = JSON.parse(tasks_response.body)
          running = tasks.count { |t| t.dig("Status", "State") == "running" }

          if running >= desired && update_status.nil?
            log_info "Service converged", service_id: service_docker_id, running: running, desired: desired
            return true
          end
        end

        sleep(CONVERGENCE_POLL_INTERVAL)
      end

      log_warn "Convergence timeout", service_id: service_docker_id
      false
    end
  end
end
