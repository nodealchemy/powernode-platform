# frozen_string_literal: true

module Ai
  # ContainerChatBridgeService - Routes chat messages to/from containerized agents
  #
  # Bridges the gap between the platform's chat system (ChatWindow, TeamChannels)
  # and agents running in Docker containers on Swarm. Handles:
  # - Routing user messages to the appropriate container
  # - Processing container responses back into conversations
  # - Auto-launching containers when a chat targets a container-enabled agent
  # - Container lifecycle management tied to conversation state
  class ContainerChatBridgeService
    class BridgeError < StandardError; end

    def initialize(account:)
      @account = account
      @deployment_service = Ai::ContainerAgentDeploymentService.new(account: account)
      @logger = Rails.logger
    end

    # Route a chat message to the agent's container
    #
    # @param conversation_id [String] the conversation ID
    # @param message [Hash] the message payload { content:, role:, metadata: }
    # @return [Hash] routing result
    def route_message_to_container(conversation_id:, message:)
      instance = find_active_instance(conversation_id)

      if instance
        forward_to_container(instance, message)
      else
        @logger.info "[ContainerChatBridge] No active container for conversation #{conversation_id}"
        { routed: false, reason: "no_active_container" }
      end
    end

    # Handle a response callback from a container
    #
    # @param conversation_id [String]
    # @param response [Hash] { content:, metadata: }
    # @return [Hash] result
    def handle_container_response(conversation_id:, response:)
      conversation = find_conversation(conversation_id)
      return { success: false, error: "Conversation not found" } unless conversation

      # Create assistant message from container response
      message = conversation.add_assistant_message(
        response[:content],
        message_type: response[:message_type] || "text",
        token_count: response.dig(:metadata, :tokens_used) || 0,
        processing_metadata: {
          source: "container",
          container_execution_id: response[:execution_id],
          model: response.dig(:metadata, :model),
          processing_time_ms: response.dig(:metadata, :processing_time_ms)
        }
      )

      @logger.info "[ContainerChatBridge] Container response saved for conversation #{conversation_id}"

      {
        success: true,
        message_id: message.id,
        conversation_id: conversation.id
      }
    rescue StandardError => e
      @logger.error "[ContainerChatBridge] Failed to handle container response: #{e.message}"
      { success: false, error: e.message }
    end

    # Ensure a container is running for a conversation
    # Finds an existing active instance or launches a new one
    #
    # @param conversation_id [String]
    # @param agent [Ai::Agent]
    # @param user [User]
    # @return [Devops::ContainerInstance, nil]
    def ensure_container_for_conversation(conversation_id:, agent:, user: nil)
      existing = find_active_instance(conversation_id)
      return existing if existing

      launch_container_for_conversation(
        conversation_id: conversation_id,
        agent: agent,
        user: user
      )
    rescue StandardError => e
      @logger.error "[ContainerChatBridge] Failed to ensure container: #{e.message}"
      nil
    end

    # Check if an agent has container execution enabled
    #
    # @param agent [Ai::Agent]
    # @return [Boolean]
    def container_enabled?(agent)
      agent.mcp_metadata&.dig("container_execution") == true
    end

    # Check if a conversation has an active container
    #
    # @param conversation_id [String]
    # @return [Boolean]
    def has_active_container?(conversation_id)
      find_active_instance(conversation_id).present?
    end

    # Terminate the container for a conversation
    #
    # @param conversation_id [String]
    # @param reason [String]
    def terminate_conversation_container(conversation_id:, reason: nil)
      instance = find_active_instance(conversation_id)
      return false unless instance

      @deployment_service.terminate_agent_session(
        container_instance: instance,
        reason: reason || "Conversation ended"
      )
    end

    private

    def find_active_instance(conversation_id)
      @account.container_instances
              .active
              .where("input_parameters->>'conversation_id' = ?", conversation_id.to_s)
              .order(created_at: :desc)
              .first
    end

    def find_conversation(conversation_id)
      @account.ai_conversations.find_by(id: conversation_id) ||
        @account.ai_conversations.find_by(conversation_id: conversation_id)
    end

    def forward_to_container(instance, message)
      # Store message routing info in input_parameters
      instance.update!(
        input_parameters: (instance.input_parameters || {}).merge(
          "last_message_at" => Time.current.iso8601,
          "messages_routed" => (instance.input_parameters&.dig("messages_routed") || 0) + 1
        )
      )

      {
        routed: true,
        container_execution_id: instance.execution_id,
        container_status: instance.status
      }
    end

    def launch_container_for_conversation(conversation_id:, agent:, user:)
      @logger.info "[ContainerChatBridge] Launching container for conversation #{conversation_id}"

      @deployment_service.deploy_agent_session(
        agent: agent,
        conversation_id: conversation_id,
        user: user
      )
    end
  end
end
