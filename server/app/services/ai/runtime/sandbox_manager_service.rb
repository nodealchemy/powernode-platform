# frozen_string_literal: true

module Ai
  module Runtime
    class SandboxManagerService
      class SandboxError < StandardError; end
      class ExecutionGateError < SandboxError; end

      TRUST_LEVEL_IMAGES = {
        "supervised" => { image: "powernode-agent-base",  tag: "latest" },
        "monitored"  => { image: "powernode-agent-code",  tag: "latest" },
        "trusted"    => { image: "powernode-agent-full",  tag: "latest" },
        "autonomous" => { image: "powernode-agent-full",  tag: "latest" }
      }.freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Create a sandbox container for an agent
      #
      # @param agent [Ai::Agent] the agent to sandbox
      # @param config [Hash] additional configuration (environment, volumes, labels)
      # @return [Devops::ContainerInstance] the sandbox instance
      def create_sandbox(agent:, config: {})
        # Execution gate check — enforce governance before provisioning
        check_execution_gate!(agent)

        template = find_or_create_template(agent, config)

        # Provision MCP OAuth credentials for the container
        mcp_auth = Ai::ContainerMcpAuthService.new.provision_mcp_credentials(agent: agent, account: account)
        mcp_env_vars = mcp_auth[:env_vars]
        oauth_app = mcp_auth[:oauth_application]

        env_vars = (config[:environment] || {}).merge(mcp_env_vars)

        instance = Devops::ContainerInstance.create!(
          account: account,
          template: template,
          image_name: template.image_name,
          image_tag: template.image_tag,
          status: "pending",
          timeout_seconds: template.timeout_seconds,
          sandbox_enabled: true,
          oauth_application: oauth_app,
          input_parameters: {
            "agent_id" => agent.id,
            "agent_name" => agent.name,
            "sandbox_mode" => true,
            "trust_level" => agent.try(:trust_level) || "supervised"
          }.merge(config.slice(:environment, :volumes, :labels).stringify_keys),
          environment_variables: env_vars,
          runner_labels: ["powernode-ai-agent", "sandbox"]
        )

        # Allocate MCP bridge port
        allocate_mcp_port!(instance)

        Rails.logger.info("[SandboxManager] Created sandbox #{instance.execution_id} for agent #{agent.id} with MCP auth")
        instance
      rescue StandardError => e
        Rails.logger.error("[SandboxManager] Failed to create sandbox for agent #{agent.id}: #{e.message}")
        raise
      end

      # Destroy a sandbox instance
      #
      # @param instance [Devops::ContainerInstance] the sandbox to destroy
      # @param reason [String] reason for destruction
      # @return [Boolean] whether destruction was successful
      def destroy_sandbox(instance:, reason: nil)
        return false unless instance.active?

        instance.cancel!(reason: reason || "Sandbox destroyed")
        Rails.logger.info("[SandboxManager] Destroyed sandbox #{instance.execution_id}")
        true
      rescue StandardError => e
        Rails.logger.error("[SandboxManager] Failed to destroy sandbox #{instance.execution_id}: #{e.message}")
        raise
      end

      # Pause a running sandbox
      #
      # @param instance [Devops::ContainerInstance] the sandbox to pause
      # @return [Hash] result with success status
      def pause_sandbox(instance:)
        unless instance.running?
          return { success: false, error: "Instance is not running (status: #{instance.status})" }
        end

        docker_host = find_docker_host(instance)
        return { success: false, error: "No docker host found" } unless docker_host

        Rails.logger.info("[SandboxManager] Pausing sandbox #{instance.execution_id}")
        instance.update!(status: "paused") if instance.respond_to?(:status=)
        { success: true, execution_id: instance.execution_id }
      end

      # Resume a paused sandbox
      #
      # @param instance [Devops::ContainerInstance] the sandbox to resume
      # @return [Hash] result with success status
      def resume_sandbox(instance:)
        docker_host = find_docker_host(instance)
        return { success: false, error: "No docker host found" } unless docker_host

        Rails.logger.info("[SandboxManager] Resuming sandbox #{instance.execution_id}")
        instance.update!(status: "running") if instance.respond_to?(:status=)
        { success: true, execution_id: instance.execution_id }
      end

      # Execute a command in a running sandbox
      #
      # @param instance [Devops::ContainerInstance] the sandbox
      # @param command [String] command to execute
      # @return [Hash] result with success status
      def exec_in_sandbox(instance:, command:)
        unless instance.running?
          return { success: false, error: "Instance is not running" }
        end

        docker_host = find_docker_host(instance)
        return { success: false, error: "No docker host found" } unless docker_host

        Rails.logger.info("[SandboxManager] Executing command in sandbox #{instance.execution_id}")
        { success: true, execution_id: instance.execution_id, command: command }
      end

      # Stream logs from a sandbox
      #
      # @param instance [Devops::ContainerInstance] the sandbox
      # @return [Hash] result with success status
      def stream_logs(instance:)
        Rails.logger.info("[SandboxManager] Streaming logs for sandbox #{instance.execution_id}")
        { success: true, execution_id: instance.execution_id }
      end

      # Get resource metrics for a sandbox
      #
      # @param instance [Devops::ContainerInstance] the sandbox
      # @return [Hash] resource metrics
      def get_metrics(instance:)
        {
          execution_id: instance.execution_id,
          status: instance.status,
          memory_used_mb: instance.try(:memory_used_mb),
          cpu_used_millicores: instance.try(:cpu_used_millicores),
          storage_used_bytes: instance.try(:storage_used_bytes),
          network_bytes_in: instance.try(:network_bytes_in),
          network_bytes_out: instance.try(:network_bytes_out),
          uptime_seconds: instance.started_at ? (Time.current - instance.started_at).to_i : nil
        }
      end

      private

      def find_or_create_template(agent, config)
        trust_level = agent.try(:trust_level) || "supervised"
        template_name = "ai-sandbox-#{trust_level}"

        # Resolve trust-level image from Gitea registry, falling back to default
        image_config = resolve_trust_level_image(trust_level, config)

        Devops::ContainerTemplate.find_or_create_by!(
          account_id: account.id,
          name: template_name
        ) do |t|
          t.category = "ai-agent"
          t.image_name = image_config[:image_name]
          t.image_tag = image_config[:image_tag]
          t.registry_url = image_config[:registry_url]
          t.visibility = "private"
          t.status = "active"
          t.sandbox_mode = true
          t.read_only_root = trust_level != "autonomous"
          t.privileged = false
          t.network_access = trust_level != "supervised"
          t.security_options = default_security_options(trust_level)
          t.resource_limits = default_resource_limits(trust_level)
          t.memory_mb = resource_memory_mb(trust_level)
          t.cpu_millicores = resource_cpu_millicores(trust_level)
        end
      end

      def resolve_trust_level_image(trust_level, config)
        # Honor explicit overrides from config
        if config[:image_name]
          return {
            image_name: config[:image_name],
            image_tag: config[:image_tag] || "latest",
            registry_url: config[:registry_url]
          }
        end

        # Map trust level to Gitea registry image variant
        variant = TRUST_LEVEL_IMAGES[trust_level] || TRUST_LEVEL_IMAGES["supervised"]
        registry_url = ENV["POWERNODE_REGISTRY_URL"]

        if registry_url.present?
          {
            image_name: variant[:image],
            image_tag: variant[:tag],
            registry_url: registry_url
          }
        else
          # Fallback to default image if Gitea registry not configured
          {
            image_name: "powernode/agent-sandbox",
            image_tag: "latest",
            registry_url: nil
          }
        end
      end

      def check_execution_gate!(agent)
        gate = Ai::Autonomy::ExecutionGateService.new(account: account)
        decision = gate.check(agent: agent, action_type: "container_execute")
        unless decision[:decision] == :proceed
          raise ExecutionGateError, "Blocked: #{decision[:reason]}"
        end
      end

      def allocate_mcp_port!(instance)
        host_id = find_docker_host(instance)&.try(:identifier) || "localhost"
        port = Devops::PortAllocatorService.new.allocate!(
          host_identifier: host_id,
          allocatable: instance,
          purpose: "mcp_bridge",
          expires_at: (instance.timeout_seconds || 3600).seconds.from_now
        )
        instance.update!(
          mcp_bridge_port: port,
          environment_variables: instance.environment_variables.merge("POWERNODE_MCP_BRIDGE_PORT" => port.to_s)
        )
      rescue Devops::PortAllocatorService::AllocationError => e
        Rails.logger.warn "[SandboxManager] Port allocation failed: #{e.message} — continuing without dedicated port"
      end

      def default_security_options(trust_level)
        {
          "cap_drop" => ["ALL"],
          "no_new_privileges" => true,
          "sandbox_mode" => true
        }
      end

      def default_resource_limits(trust_level)
        case trust_level
        when "supervised"
          { "cpu" => "0.5", "memory" => "256m", "disk" => "1g" }
        when "monitored"
          { "cpu" => "1.0", "memory" => "512m", "disk" => "2g" }
        when "trusted"
          { "cpu" => "2.0", "memory" => "1g", "disk" => "5g" }
        when "autonomous"
          { "cpu" => "4.0", "memory" => "2g", "disk" => "10g" }
        else
          { "cpu" => "0.5", "memory" => "256m", "disk" => "1g" }
        end
      end

      def resource_memory_mb(trust_level)
        case trust_level
        when "supervised" then 256
        when "monitored" then 512
        when "trusted" then 1024
        when "autonomous" then 2048
        else 256
        end
      end

      def resource_cpu_millicores(trust_level)
        case trust_level
        when "supervised" then 500
        when "monitored" then 1000
        when "trusted" then 2000
        when "autonomous" then 4000
        else 500
        end
      end

      def find_docker_host(instance)
        instance.try(:template)&.try(:docker_host) ||
          Devops::DockerHost.where(account_id: account.id).connected.first
      end
    end
  end
end
