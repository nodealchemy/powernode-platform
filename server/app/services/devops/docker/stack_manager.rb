# frozen_string_literal: true

module Devops
  module Docker
    class StackManager
      STACK_LABEL = "com.docker.stack.namespace"

      def initialize(cluster:, user: nil)
        @cluster = cluster
        @user = user
        @client = ApiClient.new(cluster)
      end

      def deploy_stack(stack)
        compose = parse_compose(stack.compose_file)
        return { success: false, error: "Invalid compose file" } unless compose

        services = compose["services"] || {}
        return { success: false, error: "No services defined in compose file" } if services.empty?

        deployment = create_deployment("stack_deploy", stack: stack, desired_state: { services: services.keys })

        begin
          stack.update!(status: "deploying")

          results = services.map do |service_name, service_config|
            deploy_stack_service(stack, service_name, service_config)
          end

          failures = results.select { |r| !r[:success] }

          if failures.any?
            stack.update!(status: "failed")
            fail_deployment(deployment, error: failures.map { |f| f[:error] }.join("; "))
            { success: false, errors: failures.map { |f| f[:error] }, deployment: deployment }
          else
            stack.update!(
              status: "deployed",
              service_count: results.size,
              last_deployed_at: Time.current,
              deploy_count: stack.deploy_count + 1
            )
            complete_deployment(deployment, result: { services_deployed: results.size })
            Rails.logger.info("Deployed stack #{stack.name} with #{results.size} services")
            { success: true, services_deployed: results.size, deployment: deployment }
          end
        rescue StandardError => e
          stack.update!(status: "failed")
          fail_deployment(deployment, error: e.message)
          Rails.logger.error("Failed to deploy stack #{stack.name}: #{e.message}")
          { success: false, error: e.message, deployment: deployment }
        end
      end

      def remove_stack(stack)
        deployment = create_deployment("stack_remove", stack: stack, previous_state: { name: stack.name })

        begin
          stack.update!(status: "removing")

          # Find and remove all services with this stack's label
          all_services = @client.service_list
          stack_services = all_services.select do |svc|
            svc.dig("Spec", "Labels", STACK_LABEL) == stack.name
          end

          stack_services.each do |svc|
            @client.service_delete(svc["ID"])
          end

          # Remove local service records
          @cluster.swarm_services.where(stack: stack).destroy_all

          stack.update!(status: "removed", service_count: 0)
          complete_deployment(deployment, result: { services_removed: stack_services.size })
          Rails.logger.info("Removed stack #{stack.name} (#{stack_services.size} services)")
          { success: true, services_removed: stack_services.size, deployment: deployment }
        rescue ApiClient::ApiError => e
          stack.update!(status: "failed")
          fail_deployment(deployment, error: e.message)
          Rails.logger.error("Failed to remove stack #{stack.name}: #{e.message}")
          { success: false, error: e.message, deployment: deployment }
        end
      end

      def list_stack_services(stack)
        all_services = @client.service_list
        all_services.select do |svc|
          svc.dig("Spec", "Labels", STACK_LABEL) == stack.name
        end
      rescue ApiClient::ApiError => e
        Rails.logger.error("Failed to list services for stack #{stack.name}: #{e.message}")
        raise
      end

      def update_stack(stack, compose_file)
        stack.update!(compose_file: compose_file)
        deploy_stack(stack)
      end

      private

      def parse_compose(compose_content)
        return nil if compose_content.blank?

        YAML.safe_load(compose_content, permitted_classes: [Symbol])
      rescue Psych::SyntaxError => e
        Rails.logger.error("Failed to parse compose YAML: #{e.message}")
        nil
      end

      def deploy_stack_service(stack, service_name, config)
        full_name = "#{stack.name}_#{service_name}"

        spec = build_service_spec(full_name, config, stack.name, stack.compose_variables)

        # Check if service already exists
        existing = @cluster.swarm_services.find_by(service_name: full_name, stack: stack)

        if existing
          # Update existing service
          docker_service = @client.service_inspect(existing.docker_service_id)
          version = docker_service.dig("Version", "Index")
          @client.service_update(existing.docker_service_id, version, spec)
          { success: true, action: "updated", name: full_name }
        else
          # Create new service
          result = @client.service_create(spec)
          docker_service = @client.service_inspect(result["ID"])
          sync_stack_service(docker_service, stack)
          { success: true, action: "created", name: full_name }
        end
      rescue ApiClient::ApiError => e
        { success: false, name: full_name, error: e.message }
      end

      def build_service_spec(name, config, stack_name, variables = {})
        image = interpolate_variables(config["image"] || "", variables)

        spec = {
          "Name" => name,
          "Labels" => (config["labels"] || {}).merge(STACK_LABEL => stack_name),
          "TaskTemplate" => {
            "ContainerSpec" => {
              "Image" => image,
              "Env" => build_environment(config["environment"], variables)
            }
          }
        }

        # Replicas
        replicas = config.dig("deploy", "replicas") || 1
        mode = config.dig("deploy", "mode") || "replicated"
        if mode == "global"
          spec["Mode"] = { "Global" => {} }
        else
          spec["Mode"] = { "Replicated" => { "Replicas" => replicas.to_i } }
        end

        # Ports
        if config["ports"].present?
          spec["EndpointSpec"] = { "Ports" => build_ports(config["ports"]) }
        end

        # Resource limits
        if config.dig("deploy", "resources")
          spec["TaskTemplate"]["Resources"] = build_resources(config.dig("deploy", "resources"))
        end

        # Placement constraints
        if config.dig("deploy", "placement", "constraints")
          spec["TaskTemplate"]["Placement"] = {
            "Constraints" => config.dig("deploy", "placement", "constraints")
          }
        end

        # Update config
        if config.dig("deploy", "update_config")
          spec["UpdateConfig"] = build_update_config(config.dig("deploy", "update_config"))
        end

        # Networks
        if config["networks"].present?
          spec["TaskTemplate"]["Networks"] = config["networks"].map do |network_name|
            { "Target" => "#{stack_name}_#{network_name}" }
          end
        end

        spec
      end

      def build_environment(env_config, variables = {})
        return [] if env_config.blank?

        case env_config
        when Array
          env_config.map { |e| interpolate_variables(e.to_s, variables) }
        when Hash
          env_config.map { |k, v| "#{k}=#{interpolate_variables(v.to_s, variables)}" }
        else
          []
        end
      end

      def build_ports(ports_config)
        return [] if ports_config.blank?

        ports_config.map do |port|
          case port
          when String
            parts = port.split(":")
            if parts.size == 2
              { "Protocol" => "tcp", "TargetPort" => parts[1].to_i, "PublishedPort" => parts[0].to_i }
            else
              { "Protocol" => "tcp", "TargetPort" => parts[0].to_i }
            end
          when Hash
            {
              "Protocol" => port["protocol"] || "tcp",
              "TargetPort" => port["target"].to_i,
              "PublishedPort" => port["published"]&.to_i
            }.compact
          end
        end.compact
      end

      def build_resources(resources_config)
        result = {}

        if resources_config["limits"]
          result["Limits"] = {}
          result["Limits"]["NanoCPUs"] = parse_cpu(resources_config.dig("limits", "cpus")) if resources_config.dig("limits", "cpus")
          result["Limits"]["MemoryBytes"] = parse_memory(resources_config.dig("limits", "memory")) if resources_config.dig("limits", "memory")
        end

        if resources_config["reservations"]
          result["Reservations"] = {}
          result["Reservations"]["NanoCPUs"] = parse_cpu(resources_config.dig("reservations", "cpus")) if resources_config.dig("reservations", "cpus")
          result["Reservations"]["MemoryBytes"] = parse_memory(resources_config.dig("reservations", "memory")) if resources_config.dig("reservations", "memory")
        end

        result
      end

      def build_update_config(config)
        result = {}
        result["Parallelism"] = config["parallelism"].to_i if config["parallelism"]
        result["Delay"] = parse_duration(config["delay"]) if config["delay"]
        result["FailureAction"] = config["failure_action"] if config["failure_action"]
        result["Order"] = config["order"] if config["order"]
        result
      end

      def parse_cpu(value)
        (value.to_f * 1_000_000_000).to_i
      end

      def parse_memory(value)
        value = value.to_s
        case value
        when /(\d+)g$/i then Regexp.last_match(1).to_i * 1024 * 1024 * 1024
        when /(\d+)m$/i then Regexp.last_match(1).to_i * 1024 * 1024
        when /(\d+)k$/i then Regexp.last_match(1).to_i * 1024
        else value.to_i
        end
      end

      def parse_duration(value)
        value = value.to_s
        case value
        when /(\d+)s$/  then Regexp.last_match(1).to_i * 1_000_000_000
        when /(\d+)ms$/ then Regexp.last_match(1).to_i * 1_000_000
        when /(\d+)m$/  then Regexp.last_match(1).to_i * 60 * 1_000_000_000
        else value.to_i
        end
      end

      def interpolate_variables(str, variables)
        return str if variables.blank?

        variables.each do |key, value|
          str = str.gsub("${#{key}}", value.to_s)
          str = str.gsub("$#{key}", value.to_s)
        end
        str
      end

      def sync_stack_service(docker_service, stack)
        spec = docker_service["Spec"] || {}
        task_template = spec["TaskTemplate"] || {}

        service = @cluster.swarm_services.find_or_initialize_by(
          docker_service_id: docker_service["ID"]
        )

        service.assign_attributes(
          stack: stack,
          service_name: spec["Name"] || "unknown",
          image: task_template.dig("ContainerSpec", "Image") || "unknown",
          mode: spec.dig("Mode", "Replicated") ? "replicated" : "global",
          desired_replicas: spec.dig("Mode", "Replicated", "Replicas") || 1,
          labels: spec["Labels"] || {},
          environment: task_template.dig("ContainerSpec", "Env") || [],
          version: docker_service.dig("Version", "Index")
        )
        service.save!
      end

      def create_deployment(type, stack:, previous_state: {}, desired_state: {})
        @cluster.swarm_deployments.create!(
          deployment_type: type,
          stack: stack,
          triggered_by: @user,
          status: "running",
          previous_state: previous_state,
          desired_state: desired_state,
          started_at: Time.current,
          trigger_source: "api"
        )
      end

      def complete_deployment(deployment, result: {})
        deployment.update!(
          status: "completed",
          result: result,
          completed_at: Time.current,
          duration_ms: ((Time.current - deployment.started_at) * 1000).to_i
        )
      end

      def fail_deployment(deployment, error:)
        deployment.update!(
          status: "failed",
          result: { error: error },
          completed_at: Time.current,
          duration_ms: ((Time.current - deployment.started_at) * 1000).to_i
        )
      end
    end
  end
end
