import { BaseApiService } from '@/shared/services/ai/BaseApiService';

export interface AgentConnectionNode {
  id: string;
  type: 'agent' | 'peer_agent' | 'team' | 'mcp_server' | 'memory_pool';
  name: string;
  status: string;
  metadata: Record<string, unknown>;
}

export interface AgentConnectionEdge {
  source: string;
  target: string;
  relationship: string;
  label: string;
}

export interface AgentConnectionsSummary {
  teams: number;
  peers: number;
  mcp_servers: number;
  connections: number;
}

export interface AgentConnectionsResponse {
  nodes: AgentConnectionNode[];
  edges: AgentConnectionEdge[];
  summary: AgentConnectionsSummary;
}

class AgentConnectionsApiService extends BaseApiService {
  async getAgentConnections(agentId: string): Promise<AgentConnectionsResponse> {
    const path = this.buildPath('agents', agentId, undefined, undefined, 'connections');
    return this.get<AgentConnectionsResponse>(path);
  }
}

export const agentConnectionsApi = new AgentConnectionsApiService();
