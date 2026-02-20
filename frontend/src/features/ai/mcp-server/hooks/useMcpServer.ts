import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type { McpToken, McpTokenCreateResponse, McpSession, CreateMcpTokenParams } from '../types';

const MCP_SERVER_KEYS = {
  tokens: ['mcp-tokens'] as const,
  sessions: ['mcp-sessions'] as const,
};

// ─── Token Hooks ─────────────────────────────────────────

export function useMcpTokens() {
  return useQuery({
    queryKey: MCP_SERVER_KEYS.tokens,
    queryFn: async () => {
      const response = await apiClient.get('/mcp/tokens');
      return (response.data?.data || []) as McpToken[];
    },
  });
}

export function useCreateMcpToken() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: CreateMcpTokenParams) => {
      const response = await apiClient.post('/mcp/tokens', params);
      return response.data?.data as McpTokenCreateResponse;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: MCP_SERVER_KEYS.tokens });
    },
  });
}

export function useRevokeMcpToken() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (tokenId: string) => {
      const response = await apiClient.delete(`/mcp/tokens/${tokenId}`);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: MCP_SERVER_KEYS.tokens });
    },
  });
}

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
