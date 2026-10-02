import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import { mcpApi } from '@/shared/services/ai/McpApiService';
import type { McpSession, McpSecurityServer, McpServerSecurity } from '../types';

const MCP_SERVER_KEYS = {
  sessions: ['mcp-sessions'] as const,
  security: ['mcp-security-servers'] as const,
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

// ─── Sandbox security (IMP-cdda895b07a8) ─────────────────

interface RawSecurityServer {
  id: string;
  name: string;
  status: string;
  command?: string | null;
  connection_type: string;
  security?: Partial<McpServerSecurity>;
}

const normalizeSecurity = (raw?: Partial<McpServerSecurity>): McpServerSecurity => ({
  allow_network: raw?.allow_network === true,
  allow_extended_commands: raw?.allow_extended_commands === true,
  egress_allowlist: Array.isArray(raw?.egress_allowlist) ? raw.egress_allowlist : [],
});

/** The account's stdio servers with their sandbox capabilities (the sandbox only applies to stdio). */
export function useMcpSecurityServers() {
  return useQuery({
    queryKey: MCP_SERVER_KEYS.security,
    queryFn: async () => {
      const servers = await mcpApi.getStdioServersRaw<RawSecurityServer>();
      return servers
        .filter((s) => s.connection_type === 'stdio')
        .map<McpSecurityServer>((s) => ({
          id: s.id,
          name: s.name,
          status: s.status,
          command: s.command ?? null,
          security: normalizeSecurity(s.security),
        }));
    },
  });
}

/** Partial update: only the keys present are sent and changed. The server's own validations are the rules. */
export function useUpdateMcpServerSecurity() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ serverId, security }: { serverId: string; security: Partial<McpServerSecurity> }) => {
      return mcpApi.updateServerSecurity<unknown>(serverId, security);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: MCP_SERVER_KEYS.security });
    },
  });
}
