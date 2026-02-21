import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type { McpSession } from '../types';

const MCP_SERVER_KEYS = {
  sessions: ['mcp-sessions'] as const,
};

// ─── Session Hooks ───────────────────────────────────────

export function useMcpSessions() {
  return useQuery({
    queryKey: MCP_SERVER_KEYS.sessions,
    queryFn: async () => {
      const response = await apiClient.get('/mcp/sessions');
      return (response.data?.data || []) as McpSession[];
    },
    refetchInterval: 30000, // Auto-refresh every 30s
  });
}

export function useRevokeMcpSession() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (sessionId: string) => {
      const response = await apiClient.delete(`/mcp/sessions/${sessionId}`);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: MCP_SERVER_KEYS.sessions });
    },
  });
}
