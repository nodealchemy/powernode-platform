import { useState, useEffect, useCallback } from 'react';
import { apiClient } from '@/shared/services/apiClient';
import { McpServerForWorkflowBuilder } from '@/shared/types/workflow';

interface UseMcpServersForWorkflowResult {
  servers: McpServerForWorkflowBuilder[];
  loading: boolean;
  error: string | null;
  totalServers: number;
  totalTools: number;
  refetch: () => Promise<void>;
}

interface McpServersForWorkflowResponse {
  mcp_servers: McpServerForWorkflowBuilder[];
  meta: {
    total_servers: number;
    total_tools: number;
  };
}

/**
 * Hook to fetch connected MCP servers with their tools, resources, and prompts
 * for the workflow builder.
 *
 * Only returns servers that are connected and ready to use.
 */
export function useMcpServersForWorkflow(): UseMcpServersForWorkflowResult {
  const [servers, setServers] = useState<McpServerForWorkflowBuilder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [totalServers, setTotalServers] = useState(0);
  const [totalTools, setTotalTools] = useState(0);

  const fetchServers = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const response = await apiClient.get<McpServersForWorkflowResponse>(
        '/mcp_servers/for_workflow_builder'
      );

      setServers(response.data?.mcp_servers || []);
      setTotalServers(response.data?.meta?.total_servers || 0);
      setTotalTools(response.data?.meta?.total_tools || 0);
    } catch {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch MCP servers';
      setError(errorMessage);
      setServers([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchServers();
  }, [fetchServers]);

  return {
    servers,
    loading,
    error,
    totalServers,
    totalTools,
    refetch: fetchServers,
  };
}

/**
 * Hook to get a specific MCP server by ID from the workflow builder data
 */
export function useMcpServerForWorkflow(serverId: string | undefined): {
  server: McpServerForWorkflowBuilder | null;
  loading: boolean;
  error: string | null;
} {
  const { servers, loading, error } = useMcpServersForWorkflow();

  const server = serverId
    ? servers.find(s => s.id === serverId) || null
    : null;

  return { server, loading, error };
}
