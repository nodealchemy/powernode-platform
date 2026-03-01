# frozen_string_literal: true

require "faraday"
require "openssl"
require "yaml"

module Swarm
  # Deploys a Docker Swarm stack from compose YAML
  # Queue: devops_high
  # Retry: 1
  class StackDeployJob < BaseJob
    sidekiq_options queue: "devops_high", retry: 1

    DOCKER_API_VERSION = "v1.41"
    CONVERGENCE_TIMEOUT = 300
    CONVERGENCE_POLL_INTERVAL = 5

    # Deploy a stack
    # @param deployment_id [String] The deployment ID
    def execute(deployment_id)
      log_info "Starting stack deployment", deployment_id: deployment_id

      # Fetch deployment details
      deployment = fetch_deployment(deployment_id)
      update_deployment_status(deployment_id, "in_progress", started_at: Time.current.iso8601)

      # Get Docker connection
      connection = fetch_connection_details(deployment["cluster_id"])
      docker = build_docker_client(connection)

      # Parse compose YAML
      compose = parse_compose(deployment["compose_yaml"])
      stack_name = deployment["stack_name"]

      # Deploy each service in the compose spec
      deployed_services = []
      compose.fetch("services", {}).each do |service_name, service_spec|
        full_name = "#{stack_name}_#{service_name}"
        log_info "Deploying service", service: full_name

        docker_spec = translate_compose_to_docker(service_name, service_spec, stack_name)

        # Check if service already exists
        existing = find_existing_service(docker, full_name)

        if existing
          update_docker_service(docker, existing["ID"], existing["Version"]["Index"], docker_spec)
        else
          create_docker_service(docker, docker_spec)
        end

        deployed_services << full_name
      end

      # Wait for convergence
      converged = wait_for_convergence(docker, deployed_services)

      status = converged ? "completed" : "partially_converged"
      update_deployment_status(deployment_id, status, {
        completed_at: Time.current.iso8601,
        result: { services: deployed_services, converged: converged }
      })

      log_info "Stack deployment finished",
               deployment_id: deployment_id,
               status: status,
               services: deployed_services.size
    rescue StandardError => e
      log_error "Stack deployment failed", e, deployment_id: deployment_id
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

    def parse_compose(compose_yaml)
      parsed = YAML.safe_load(compose_yaml)
      raise "Invalid compose file: missing 'services' key" unless parsed.is_a?(Hash) && parsed.key?("services")

      parsed
    end

    def translate_compose_to_docker(service_name, spec, stack_name)
      full_name = "#{stack_name}_#{service_name}"

      docker_spec = {
        "Name" => full_name,
        "Labels" => {
          "com.docker.stack.namespace" => stack_name,
          "com.docker.stack.image" => spec["image"]
        }.merge(spec.fetch("labels", {})),
        "TaskTemplate" => {
          "ContainerSpec" => {
            "Image" => spec["image"],
            "Env" => build_env_array(spec.fetch("environment", {}))
          }.tap do |container|
            container["Command"] = spec["command"].split if spec["command"].is_a?(String)
            container["Command"] = spec["command"] if spec["command"].is_a?(Array)
          end,
          "Resources" => build_resources(spec.fetch("deploy", {}).fetch("resources", {})),
          "RestartPolicy" => build_restart_policy(spec.dig("deploy", "restart_policy"))
        },
        "Mode" => build_mode(spec.fetch("deploy", {})),
        "EndpointSpec" => build_endpoint_spec(spec.fetch("ports", []))
      }

      # Add network attachments
      if spec["networks"]
        docker_spec["TaskTemplate"]["Networks"] = spec["networks"].map do |net|
          net.is_a?(String) ? { "Target" => "#{stack_name}_#{net}" } : { "Target" => "#{stack_name}_#{net.keys.first}" }
        end
      end

      docker_spec
    end

    def build_env_array(env)
      case env
      when Array
        env
      when Hash
        env.map { |k, v| "#{k}=#{v}" }
      else
        []
      end
    end

    def build_resources(resources)
      result = {}

      if resources["limits"]
        result["Limits"] = {}
        result["Limits"]["NanoCPUs"] = parse_cpu(resources["limits"]["cpus"]) if resources["limits"]["cpus"]
        result["Limits"]["MemoryBytes"] = parse_memory(resources["limits"]["memory"]) if resources["limits"]["memory"]
      end

      if resources["reservations"]
        result["Reservations"] = {}
        result["Reservations"]["NanoCPUs"] = parse_cpu(resources["reservations"]["cpus"]) if resources["reservations"]["cpus"]
        result["Reservations"]["MemoryBytes"] = parse_memory(resources["reservations"]["memory"]) if resources["reservations"]["memory"]
      end

      result
    end

    def parse_cpu(value)
      (value.to_f * 1_000_000_000).to_i
    end

    def parse_memory(value)
      case value.to_s
      when /(\d+)g/i then Regexp.last_match(1).to_i * 1024 * 1024 * 1024
      when /(\d+)m/i then Regexp.last_match(1).to_i * 1024 * 1024
      when /(\d+)k/i then Regexp.last_match(1).to_i * 1024
      else value.to_i
      end
    end

    def build_mode(deploy)
      if deploy.dig("mode") == "global"
        { "Global" => {} }
      else
        replicas = deploy.fetch("replicas", 1).to_i
        { "Replicated" => { "Replicas" => replicas } }
      end
    end

    def build_restart_policy(policy)
      return { "Condition" => "any", "MaxAttempts" => 3 } unless policy

      {
        "Condition" => policy.fetch("condition", "any"),
        "Delay" => parse_duration(policy["delay"]),
        "MaxAttempts" => policy.fetch("max_attempts", 3).to_i,
        "Window" => parse_duration(policy["window"])
      }.compact
    end

    def parse_duration(value)
      return nil unless value

      case value.to_s
      when /(\d+)s/ then Regexp.last_match(1).to_i * 1_000_000_000
      when /(\d+)m/ then Regexp.last_match(1).to_i * 60 * 1_000_000_000
      when /(\d+)h/ then Regexp.last_match(1).to_i * 3600 * 1_000_000_000
      else value.to_i * 1_000_000_000
      end
    end

    def build_endpoint_spec(ports)
      return {} if ports.empty?

      {
        "Ports" => ports.map do |port|
          case port
          when String
            host, container = port.split(":")
            { "Protocol" => "tcp", "PublishedPort" => host.to_i, "TargetPort" => container.to_i, "PublishMode" => "ingress" }
          when Hash
            { "Protocol" => port.fetch("protocol", "tcp"), "PublishedPort" => port["published"].to_i,
              "TargetPort" => port["target"].to_i, "PublishMode" => port.fetch("mode", "ingress") }
          end
        end.compact
      }
    end

    def find_existing_service(docker, service_name)
      response = docker.get("/services", filters: { name: [service_name] }.to_json)
      return nil unless response.success?

      services = JSON.parse(response.body)
      services.find { |s| s.dig("Spec", "Name") == service_name }
    end

    def create_docker_service(docker, spec)
      response = docker.post("/services/create") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = spec.to_json
      end

      unless response.success?
        raise "Failed to create service '#{spec['Name']}': #{response.status} - #{response.body}"
      end

      JSON.parse(response.body)
    end

    def update_docker_service(docker, service_id, version_index, spec)
      response = docker.post("/services/#{service_id}/update?version=#{version_index}") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = spec.to_json
      end

      unless response.success?
        raise "Failed to update service '#{spec['Name']}': #{response.status} - #{response.body}"
      end
    end

    def wait_for_convergence(docker, service_names)
      deadline = Time.current + CONVERGENCE_TIMEOUT

      until Time.current > deadline
        all_converged = service_names.all? do |name|
          service = find_existing_service(docker, name)
          next false unless service

          desired = service.dig("Spec", "Mode", "Replicated", "Replicas") || 1
          tasks_response = docker.get("/tasks", filters: { service: [service["ID"]], "desired-state": ["running"] }.to_json)
          next false unless tasks_response.success?

          tasks = JSON.parse(tasks_response.body)
          running = tasks.count { |t| t.dig("Status", "State") == "running" }
          running >= desired
        end

        return true if all_converged

        sleep(CONVERGENCE_POLL_INTERVAL)
      end

      log_warn "Convergence timeout reached", services: service_names
      false
    end
  end
end
