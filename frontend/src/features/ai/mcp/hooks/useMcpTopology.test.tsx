import React from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useMcpTopology } from './useMcpTopology';

// fc-43 review F2: MCP › Studio is visible to a user with mcp.servers.read
// only. The topology must still render that user's servers and tools when
// the agents read (ai.agents.read) is refused — just without agent edges.

jest.mock('@/shared/services/ai/McpApiService', () => ({
  mcpApi: { getServers: jest.fn() },
}));
jest.mock('@/shared/services/ai', () => ({
  agentsApi: { getAgents: jest.fn() },
}));

import { mcpApi } from '@/shared/services/ai/McpApiService';
import { agentsApi } from '@/shared/services/ai';

const servers = {
  servers: [{ id: 's1', name: 'Filesystem', status: 'connected', tools_count: 1, connection_type: 'stdio' }],
  tools: [{ id: 't1', name: 'read_file', server_id: 's1', server_name: 'Filesystem' }],
};

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
    {children}
  </QueryClientProvider>
);

describe('useMcpTopology', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (mcpApi.getServers as jest.Mock).mockResolvedValue(servers);
  });

  it('renders servers and tools without agent edges when the agents read is forbidden', async () => {
    (agentsApi.getAgents as jest.Mock).mockRejectedValue(Object.assign(new Error('Forbidden'), { status: 403 }));

    const { result } = renderHook(() => useMcpTopology(), { wrapper });

    await waitFor(() => expect(result.current.isLoading).toBe(false));
    expect(result.current.error).toBeNull();
    expect(result.current.servers.map((s) => s.id)).toEqual(['s1']);
    expect(result.current.tools.map((t) => t.id)).toEqual(['t1']);
    expect(result.current.agents).toEqual([]);
    expect(result.current.connections.map((c) => `${c.sourceType}->${c.targetType}`)).toEqual(['server->tool']);
  });

  it('links agents to connected servers when the agents read succeeds', async () => {
    (agentsApi.getAgents as jest.Mock).mockResolvedValue({
      items: [{ id: 'a1', name: 'Planner', status: 'active', agent_type: 'assistant' }],
    });

    const { result } = renderHook(() => useMcpTopology(), { wrapper });

    await waitFor(() => expect(result.current.agents).toHaveLength(1));
    expect(result.current.connections.map((c) => c.id)).toEqual(expect.arrayContaining(['a1-s1', 's1-t1']));
  });

  it('still reports an error when the servers read itself fails', async () => {
    (mcpApi.getServers as jest.Mock).mockRejectedValue(new Error('Forbidden'));
    (agentsApi.getAgents as jest.Mock).mockResolvedValue({ items: [] });

    const { result } = renderHook(() => useMcpTopology(), { wrapper });

    await waitFor(() => expect(result.current.error).not.toBeNull());
  });
});
