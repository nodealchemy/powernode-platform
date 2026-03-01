import { useQuery } from '@tanstack/react-query';
import { mcpApi } from '@/shared/services/ai/McpApiService';
import { agentsApi } from '@/shared/services/ai';

export interface TopologyAgent {
  id: string;
  name: string;
  status: 'active' | 'inactive' | 'error';
  agent_type: string;
  serverIds: string[];
}

export interface TopologyServer {
  id: string;
  name: string;
  status: 'connected' | 'disconnected' | 'connecting' | 'error';
  tools_count: number;
  connection_type: string;
}

export interface TopologyTool {
  id: string;
  name: string;
  serverId: string;
  serverName: string;
  category?: string;
  description?: string;
}

export interface TopologyConnection {
  id: string;
  sourceId: string;
  targetId: string;
  sourceType: 'agent' | 'server';
  targetType: 'server' | 'tool';
  status: 'healthy' | 'warning' | 'error';
}

export interface McpTopologyData {
  agents: TopologyAgent[];
  servers: TopologyServer[];
  tools: TopologyTool[];
  connections: TopologyConnection[];
  isLoading: boolean;
  error: Error | null;
  refetch: () => void;
}

const TOPOLOGY_KEY = ['mcp-topology'] as const;

export function useMcpTopology(): McpTopologyData {
  const {
    data,
    isLoading,
    error,
    refetch,
  } = useQuery({
    queryKey: TOPOLOGY_KEY,
    queryFn: async () => {
      const [mcpData, agentResponse] = await Promise.all([
        mcpApi.getServers(),
        agentsApi.getAgents({ per_page: 100 }),
      ]);

      const servers: TopologyServer[] = mcpData.servers.map((s) => ({
        id: s.id,
        name: s.name,
        status: s.status,
        tools_count: s.tools_count,
        connection_type: s.connection_type,
      }));

      const tools: TopologyTool[] = mcpData.tools.map((t) => ({
        id: t.id,
        name: t.name,
        serverId: t.server_id,
        serverName: t.server_name,
        category: t.category,
        description: t.description,
      }));

      // Map agents and infer connections from metadata/mcp_metadata
      const agentItems = agentResponse.items || [];
      const serverIdSet = new Set(servers.map((s) => s.id));

      const agents: TopologyAgent[] = agentItems.map((a) => {
        // Try to extract linked MCP server IDs from mcp_metadata or metadata
        const meta = a.mcp_metadata || a.metadata || {};
        const linkedServers: string[] = [];

        if (Array.isArray(meta.mcp_server_ids)) {
          linkedServers.push(
            ...meta.mcp_server_ids.filter((id: string) => serverIdSet.has(id))
          );
        }

        // If agent has no explicit server links, link to all connected servers
        const effectiveServerIds = linkedServers.length > 0
          ? linkedServers
          : servers.filter((s) => s.status === 'connected').map((s) => s.id);

        return {
          id: a.id,
          name: a.name,
          status: a.status,
          agent_type: a.agent_type,
          serverIds: effectiveServerIds,
        };
      });

      // Build connections
      const connections: TopologyConnection[] = [];

      // Agent → Server connections
      for (const agent of agents) {
        for (const serverId of agent.serverIds) {
          const server = servers.find((s) => s.id === serverId);
          const status: TopologyConnection['status'] =
            agent.status === 'error' || server?.status === 'error'
              ? 'error'
              : server?.status === 'disconnected'
                ? 'warning'
                : 'healthy';

          connections.push({
            id: `${agent.id}-${serverId}`,
            sourceId: agent.id,
            targetId: serverId,
            sourceType: 'agent',
            targetType: 'server',
            status,
          });
        }
      }

      // Server → Tool connections
      for (const tool of tools) {
        const server = servers.find((s) => s.id === tool.serverId);
        connections.push({
          id: `${tool.serverId}-${tool.id}`,
          sourceId: tool.serverId,
          targetId: tool.id,
          sourceType: 'server',
          targetType: 'tool',
          status: server?.status === 'connected' ? 'healthy' : 'warning',
        });
      }

      return { agents, servers, tools, connections };
    },
    refetchInterval: 30000,
    staleTime: 15000,
  });

  return {
    agents: data?.agents || [],
    servers: data?.servers || [],
    tools: data?.tools || [],
    connections: data?.connections || [],
    isLoading,
    error: error as Error | null,
    refetch,
  };
}
