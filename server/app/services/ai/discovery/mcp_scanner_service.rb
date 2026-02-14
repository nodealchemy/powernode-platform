# frozen_string_literal: true

module Ai
  module Discovery
    class McpScannerService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Scan all MCP servers for tools and agent mappings
      def scan
        servers = defined?(PowernodeEnterprise::Engine) ? Mcp::HostedServer.where(account: account) : Mcp::HostedServer.none
        agents = Ai::Agent.where(account: account)

        discovered_tools = []
        discovered_agents = []
        discovered_connections = []

        servers.find_each do |server|
          tools = extract_tools(server)
          discovered_tools.concat(tools)

          matched = match_tools_to_agents(tools, agents)
          matched.each do |match|
            discovered_connections << {
              source_type: "Ai::Agent",
              source_id: match[:agent_id],
              target_type: "Mcp::HostedServer",
              target_id: server.id,
              connection_type: "mcp_tool_usage",
              strength: match[:confidence],
              metadata: { tools: match[:matched_tools] }
            }
          end
        end

        agents.find_each do |agent|
          discovered_agents << build_agent_node(agent)
        end

        {
          agents: discovered_agents,
          tools: discovered_tools,
          connections: discovered_connections
        }
      end

      # Match tools to agents based on skill/capability overlap
      def match_tools_to_agents(tools, agents)
        matches = []

        agents.find_each do |agent|
          agent_skills = extract_agent_skills(agent)
          next if agent_skills.empty?

          matched_tools = tools.select do |tool|
            tool_keywords = extract_tool_keywords(tool)
            (agent_skills & tool_keywords).any?
          end

          next if matched_tools.empty?

          confidence = [matched_tools.size.to_f / [tools.size, 1].max, 1.0].min
          matches << {
            agent_id: agent.id,
            agent_name: agent.name,
            matched_tools: matched_tools.map { |t| t[:name] },
            confidence: confidence.round(2)
          }
        end

        matches
      end

      private

      def extract_tools(server)
        tool_manifest = server.respond_to?(:tool_manifest) ? server.tool_manifest : {}
        tools = tool_manifest.is_a?(Array) ? tool_manifest : (tool_manifest["tools"] || [])

        tools.map do |tool|
          {
            name: tool["name"] || tool[:name],
            description: tool["description"] || tool[:description],
            server_id: server.id,
            server_name: server.name,
            input_schema: tool["inputSchema"] || tool["input_schema"] || {}
          }
        end
      end

      def extract_agent_skills(agent)
        skills = agent.agent_skills.pluck(:name) if agent.respond_to?(:ai_agent_skills)
        skills ||= []

        # Also consider agent capabilities from metadata
        capabilities = agent.respond_to?(:capabilities) ? (agent.capabilities || []) : []
        (skills + capabilities).map(&:downcase).uniq
      end

      def extract_tool_keywords(tool)
        name = (tool[:name] || "").downcase
        description = (tool[:description] || "").downcase

        keywords = name.split(/[_\-\s]+/)
        keywords += description.scan(/\b\w{3,}\b/)
        keywords.uniq
      end

      def build_agent_node(agent)
        {
          id: agent.id,
          type: "agent",
          name: agent.name,
          status: agent.respond_to?(:status) ? agent.status : "unknown",
          metadata: {
            provider: agent.respond_to?(:provider) ? agent.provider : nil,
            model: agent.respond_to?(:model) ? agent.model : nil
          }
        }
      end
    end
  end
end
