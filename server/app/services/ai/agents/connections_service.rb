# frozen_string_literal: true

module Ai
  module Agents
    class ConnectionsService
      def initialize(agent:, account:)
        @agent = agent
        @account = account
      end

      def call
        nodes = []
        edges = []

        # Center node: the agent itself
        nodes << agent_node(@agent, selected: true)

        # 1. Team memberships → teams + peer agents
        add_team_connections(nodes, edges)

        # 2. MCP tool usages
        add_mcp_connections(nodes, edges)

        # 3. A2A communications
        add_a2a_connections(nodes, edges)

        # 4. Shared memory pools
        add_shared_memory_connections(nodes, edges)

        # Deduplicate nodes by id
        nodes.uniq! { |n| n[:id] }

        {
          nodes: nodes,
          edges: edges,
          summary: {
            teams: nodes.count { |n| n[:type] == "team" },
            peers: nodes.count { |n| n[:type] == "peer_agent" },
            mcp_servers: nodes.count { |n| n[:type] == "mcp_server" },
            connections: edges.size
          }
        }
      end

      private

      def add_team_connections(nodes, edges)
        memberships = Ai::AgentTeamMember
          .where(ai_agent_id: @agent.id)
          .includes(team: { members: :agent })

        memberships.each do |membership|
          team = membership.team
          nodes << { id: team.id, type: "team", name: team.name, status: team.status, metadata: { member_count: team.members.size } }
          edges << { source: @agent.id, target: team.id, relationship: "team_membership", label: membership.is_lead? ? "leads" : "member of" }

          # Add peer agents from the same team
          team.members.each do |peer_member|
            next if peer_member.ai_agent_id == @agent.id

            peer = peer_member.agent
            nodes << agent_node(peer, type: "peer_agent")
            edges << { source: team.id, target: peer.id, relationship: "team_peer", label: peer_member.role }
          end
        end
      end

      def add_mcp_connections(nodes, edges)
        connections = Ai::AgentConnection
          .where(account: @account)
          .involving("Ai::Agent", @agent.id)
          .mcp_tool_usages
          .where(status: "active")

        connections.each do |conn|
          target_id = conn.source_id == @agent.id ? conn.target_id : conn.source_id
          target_type = conn.source_id == @agent.id ? conn.target_type : conn.source_type
          label = conn.metadata&.dig("tool_name") || "uses tools"

          nodes << { id: target_id, type: "mcp_server", name: target_type, status: conn.status, metadata: conn.metadata || {} }
          edges << { source: @agent.id, target: target_id, relationship: "mcp_tool_usage", label: label }
        end
      end

      def add_a2a_connections(nodes, edges)
        connections = Ai::AgentConnection
          .where(account: @account)
          .involving("Ai::Agent", @agent.id)
          .a2a_communications
          .where(status: "active")

        connections.each do |conn|
          peer_id = conn.source_id == @agent.id ? conn.target_id : conn.source_id

          peer = Ai::Agent.find_by(id: peer_id)
          next unless peer

          nodes << agent_node(peer, type: "peer_agent")
          edges << { source: @agent.id, target: peer_id, relationship: "a2a_communication", label: "communicates with" }
        end
      end

      def add_shared_memory_connections(nodes, edges)
        connections = Ai::AgentConnection
          .where(account: @account)
          .involving("Ai::Agent", @agent.id)
          .shared_memories
          .where(status: "active")

        connections.each do |conn|
          target_id = conn.source_id == @agent.id ? conn.target_id : conn.source_id
          label = conn.metadata&.dig("pool_name") || "shared memory"

          nodes << { id: target_id, type: "memory_pool", name: label, status: conn.status, metadata: conn.metadata || {} }
          edges << { source: @agent.id, target: target_id, relationship: "shared_memory", label: label }
        end
      end

      def agent_node(agent, type: "agent", selected: false)
        {
          id: agent.id,
          type: selected ? "agent" : type,
          name: agent.name,
          status: agent.status,
          metadata: {
            agent_type: agent.agent_type
          }
        }
      end
    end
  end
end
