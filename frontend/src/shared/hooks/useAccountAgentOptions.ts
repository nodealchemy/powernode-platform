import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';

export interface AgentOption {
  id: string;
  name: string;
  agent_type?: string;
}

interface AgentListItem {
  id: string;
  name: string;
  agent_type?: string;
}

/**
 * The account's agents as picker options, from the agents list
 * (GET /ai/agents) — NOT from trust scores, which only exist for agents that
 * have been scored and so hide MCP-client agents (e.g. a Claude Code session's
 * identity). `scope: 'custom'` limits it to the account's own agents (a grant
 * can only name one); the default also includes the platform's global agents.
 */
export function useAccountAgentOptions(options: { scope?: 'custom'; enabled?: boolean } = {}) {
  const { scope, enabled = true } = options;
  return useQuery({
    queryKey: ['account-agent-options', scope ?? 'all'],
    enabled,
    queryFn: async () => {
      const response = await apiClient.get('/ai/agents', {
        params: { per_page: 100, ...(scope ? { scope } : {}) },
      });
      const raw = response.data?.data;
      const items = (raw?.items ?? raw?.agents ?? []) as AgentListItem[];
      return items
        .map((a) => ({ id: a.id, name: a.name, agent_type: a.agent_type }))
        .sort((a, b) => a.name.localeCompare(b.name)) as AgentOption[];
    },
  });
}
