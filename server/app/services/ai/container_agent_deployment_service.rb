# frozen_string_literal: true

module Ai
  # ContainerAgentDeploymentService - Deploy/terminate/monitor agent containers on Docker Swarm
  #
  # Orchestrates the lifecycle of containerized agent sessions:
  # - Deploy agent containers from templates to Swarm clusters
  # - Monitor container health and resource usage
  # - Terminate sessions and clean up resources
  #
  # Uses the container-per-session pattern: each chat conversation gets an isolated
  # container, torn down on close.
  class ContainerAgentDeploymentService
    class DeploymentError < StandardError; end
    class SwarmUnavailableError < DeploymentError; end
    class TemplateNotFoundError < DeploymentError; end

    def initialize(account:)
      @account = account
      @logger = Rails.logger
    end

    # Deploy an agent session container on Swarm
    #
    # @param agent [Ai::Agent] the agent to deploy
    # @param conversation_id [String] the conversation this container serves
    # @param swarm_cluster [Devops::SwarmCluster] target Swarm cluster (auto-detected if nil)
    # @param user [User] the user who triggered deployment
    # @return [Devops::ContainerInstance] the created container instance
    def deploy_agent_session(agent:, conversation_id:, swarm_cluster: nil, user: nil)
      cluster = swarm_cluster || find_available_cluster
      template = find_chat_agent_template

      @logger.info "[ContainerAgentDeployment] Deploying agent #{agent.name} " \
                   "for conversation #{conversation_id} on cluster #{cluster.name}"

      # Create container instance record
      instance = create_container_instance(
        agent: agent,
        conversation_id: conversation_id,
        cluster: cluster,
        template: template,
        user: user
      )

      # Build Swarm service spec
      service_spec = build_service_spec(
        agent: agent,
        conversation_id: conversation_id,
        template: template,
        instance: instance
      )

      # Store the service spec in input_parameters for the worker to use
      instance.update!(
        input_parameters: (instance.input_parameters || {}).merge(
          "swarm_cluster_id" => cluster.id,
          "service_spec" => service_spec,
          "deployment_requested_at" => Time.current.iso8601
        )
      )

      instance.start_provisioning!

      @logger.info "[ContainerAgentDeployment] Container instance #{instance.execution_id} " \
                   "provisioning on #{cluster.name}"

      instance
    rescue DeploymentError
      raise
    rescue StandardError => e
      @logger.error "[ContainerAgentDeployment] Deployment failed: #{e.message}"
      instance&.fail!(e.message) if instance&.persisted? && instance&.active?
      raise DeploymentError, "Failed to deploy agent container: #{e.message}"
    end

    # Terminate a running agent session container
    #
    # @param container_instance [Devops::ContainerInstance] the instance to terminate
    # @param reason [String] optional reason for termination
    # @return [Boolean] whether termination was successful
    def terminate_agent_session(container_instance:, reason: nil)
      return false unless container_instance.active?

      @logger.info "[ContainerAgentDeployment] Terminating container #{container_instance.execution_id}"

      container_instance.cancel!(reason: reason || "Session terminated by platform")

      @logger.info "[ContainerAgentDeployment] Container #{container_instance.execution_id} terminated"
      true
    rescue StandardError => e
      @logger.error "[ContainerAgentDeployment] Termination failed: #{e.message}"
      false
    end

    # Get the status of a container session
    #
    # @param container_instance [Devops::ContainerInstance] the instance to check
    # @return [Hash] status information
    def get_session_status(container_instance:)
      {
        instance_id: container_instance.id,
        execution_id: container_instance.execution_id,
        status: container_instance.status,
        agent_id: container_instance.input_parameters&.dig("agent_id"),
        conversation_id: container_instance.input_parameters&.dig("conversation_id"),
        cluster_id: container_instance.input_parameters&.dig("swarm_cluster_id"),
        started_at: container_instance.started_at&.iso8601,
        uptime_seconds: container_instance.running? && container_instance.started_at ?
          (Time.current - container_instance.started_at).to_i : nil,
        resource_usage: {
          memory_mb: container_instance.memory_used_mb,
          cpu_millicores: container_instance.cpu_used_millicores
        }
      }
    end

    # Find all active container sessions for a conversation
    #
    # @param conversation_id [String]
    # @return [ActiveRecord::Relation]
    def active_sessions_for_conversation(conversation_id)
      @account.devops_container_instances
              .active
              .where("input_parameters->>'conversation_id' = ?", conversation_id)
    end

    private

    def find_available_cluster
      cluster = Devops::SwarmCluster.where(account_id: @account.id)
                                    .connected
                                    .first

      raise SwarmUnavailableError, "No connected Swarm cluster available" unless cluster

      cluster
    end

    def find_chat_agent_template
      template = Devops::ContainerTemplate.find_by(
        name: "Autonomous Chat Agent",
        status: "active"
      )

      # Fall back to the AI Coding Agent template
      template ||= Devops::ContainerTemplate.find_by(
        name: "AI Coding Agent",
        status: "active"
      )

      raise TemplateNotFoundError, "No chat agent container template found" unless template

      template
    end

    def create_container_instance(agent:, conversation_id:, cluster:, template:, user:)
      Devops::ContainerInstance.create!(
        account: @account,
        template: template,
        triggered_by: user,
        image_name: template.image_name,
        image_tag: template.image_tag,
        status: "pending",
        timeout_seconds: template.timeout_seconds,
        sandbox_enabled: template.sandbox_mode,
        input_parameters: {
          "agent_id" => agent.id,
          "agent_name" => agent.name,
          "conversation_id" => conversation_id,
          "system_prompt" => agent.mcp_metadata&.dig("system_prompt"),
          "model" => agent.mcp_metadata&.dig("model_config", "model"),
          "provider" => agent.mcp_metadata&.dig("model_config", "provider"),
          "cluster_name" => cluster.name,
          "template_name" => template.name,
          "chat_enabled" => true
        },
        environment_variables: build_environment_variables(agent, conversation_id, nil),
        runner_labels: %w[powernode-ai-agent chat-agent]
      )
    end

    def build_service_spec(agent:, conversation_id:, template:, instance:)
      agent_id_short = agent.id.to_s[0..7]
      conv_id_short = conversation_id.to_s[0..7]

      {
        "Name" => "powernode-agent-#{agent_id_short}-#{conv_id_short}",
        "TaskTemplate" => {
          "ContainerSpec" => {
            "Image" => "#{template.image_name}:#{template.image_tag}",
            "Env" => build_environment_variables(agent, conversation_id, instance)
                       .map { |k, v| "#{k}=#{v}" },
            "Labels" => {
              "powernode.agent_id" => agent.id,
              "powernode.conversation_id" => conversation_id,
              "powernode.chat_enabled" => "true",
              "powernode.execution_id" => instance.execution_id
            }
          },
          "Resources" => {
            "Limits" => {
              "MemoryBytes" => (template.memory_mb || 2048) * 1024 * 1024,
              "NanoCPUs" => (template.cpu_millicores || 1000) * 1_000_000
            },
            "Reservations" => {
              "MemoryBytes" => 512 * 1024 * 1024
            }
          },
          "RestartPolicy" => {
            "Condition" => "none"
          }
        },
        "Labels" => {
          "powernode.managed" => "true",
          "powernode.type" => "chat-agent"
        }
      }
    end

    def build_environment_variables(agent, conversation_id, instance)
      env = {
        "AGENT_ID" => agent.id.to_s,
        "AGENT_NAME" => agent.name,
        "CONVERSATION_ID" => conversation_id.to_s,
        "PLATFORM_CALLBACK_URL" => "http://backend:3000/api/v1/ai/agent_containers/callback",
        "HEARTBEAT_INTERVAL_SECONDS" => "30",
        "PYTHONUNBUFFERED" => "1"
      }

      env["EXECUTION_ID"] = instance.execution_id if instance

      # Add system prompt if available
      system_prompt = agent.mcp_metadata&.dig("system_prompt")
      env["SYSTEM_PROMPT"] = system_prompt if system_prompt.present?

      # Add model config
      model = agent.mcp_metadata&.dig("model_config", "model")
      env["MODEL"] = model if model.present?

      provider = agent.mcp_metadata&.dig("model_config", "provider")
      env["PROVIDER"] = provider if provider.present?

      env
    end
  end
end
