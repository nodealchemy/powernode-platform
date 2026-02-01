# frozen_string_literal: true

module A2a
  # AgentCardService - Generates and serves A2A-compliant Agent Cards
  # Implements the Agent Card specification for agent discovery
  class AgentCardService
    PLATFORM_NAME = "Powernode"
    PLATFORM_DESCRIPTION = "Subscription and workflow automation platform with AI agent orchestration"
    PROTOCOL_VERSION = "1.0.0"
    CARD_VERSION = "1.0.0"

    class << self
      # Generate the platform-level Agent Card for discovery
      # This is served at /.well-known/agent-card.json
      def platform_card(base_url)
        {
          name: PLATFORM_NAME,
          description: PLATFORM_DESCRIPTION,
          url: "#{base_url}/a2a",
          version: CARD_VERSION,
          protocolVersion: PROTOCOL_VERSION,
          provider: {
            organization: "Powernode",
            url: base_url
          },
          capabilities: {
            streaming: true,
            pushNotifications: true,
            extendedAgentCard: true,
            stateTransitionHistory: true
          },
          authentication: {
            schemes: %w[bearer api_key],
            bearer: {
              type: "http",
              scheme: "bearer",
              description: "JWT Bearer token authentication"
            },
            api_key: {
              type: "apiKey",
              in: "header",
              name: "X-API-Key",
              description: "API key authentication"
            }
          },
          defaultInputModes: ["text/plain", "application/json"],
          defaultOutputModes: ["text/plain", "application/json"],
          skills: build_platform_skills,
          documentation: {
            url: "#{base_url}/api-docs",
            specification: "https://a2a-protocol.org/latest/specification/"
          }
        }
      end

      # Generate an Agent Card for a specific agent
      def agent_card(agent_card, base_url)
        return nil unless agent_card

        {
          name: agent_card.name,
          description: agent_card.description,
          url: agent_card.endpoint_url || "#{base_url}/api/v1/ai/agent_cards/#{agent_card.id}/a2a",
          version: agent_card.card_version,
          protocolVersion: agent_card.protocol_version,
          provider: {
            organization: agent_card.provider_name || PLATFORM_NAME,
            url: agent_card.provider_url || base_url
          },
          capabilities: build_capabilities(agent_card),
          authentication: build_authentication(agent_card),
          defaultInputModes: agent_card.default_input_modes || ["application/json"],
          defaultOutputModes: agent_card.default_output_modes || ["application/json"],
          skills: build_skills(agent_card),
          documentation: {
            url: agent_card.documentation_url
          }.compact
        }
      end

      private

      def build_platform_skills
        SkillRegistry.platform_skills.map do |skill|
          {
            id: skill[:id],
            name: skill[:name],
            description: skill[:description],
            inputSchema: skill[:input_schema],
            outputSchema: skill[:output_schema],
            tags: skill[:tags] || []
          }
        end
      end

      def build_skills(agent_card)
        capabilities = agent_card.capabilities || {}
        skills = capabilities["skills"] || []

        skills.map do |skill|
          {
            id: skill["id"] || skill["name"]&.parameterize,
            name: skill["name"],
            description: skill["description"],
            inputSchema: skill["input_schema"],
            outputSchema: skill["output_schema"],
            tags: skill["tags"] || []
          }.compact
        end
      end

      def build_capabilities(agent_card)
        caps = agent_card.capabilities || {}

        {
          streaming: caps["streaming"] || false,
          pushNotifications: caps["push_notifications"] || false,
          extendedAgentCard: caps["extended_card"] || false,
          stateTransitionHistory: true
        }
      end

      def build_authentication(agent_card)
        auth = agent_card.authentication || {}
        schemes = auth["schemes"] || ["bearer"]

        result = { schemes: schemes }

        if schemes.include?("bearer")
          result[:bearer] = {
            type: "http",
            scheme: "bearer"
          }
        end

        if schemes.include?("api_key")
          result[:api_key] = {
            type: "apiKey",
            in: "header",
            name: "X-API-Key"
          }
        end

        if schemes.include?("oauth2")
          result[:oauth2] = {
            type: "oauth2",
            flows: auth["oauth2_flows"] || {}
          }
        end

        result
      end
    end
  end
end
