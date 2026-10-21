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
 * Pass `search` to narrow it server-side; one page holds at most 100.
 */
export function useAccountAgentOptions(options: { scope?: 'custom'; search?: string; enabled?: boolean } = {}) {
  const { scope, enabled = true } = options;
  // A server-side search (the agents index's `search` param), so an account
  // with more agents than one page still finds the one it wants.
  const search = options.search?.trim() || undefined;
  return useQuery({
    queryKey: ['account-agent-options', scope ?? 'all', search ?? ''],
    enabled,
    placeholderData: (previous) => previous,
    queryFn: async () => {
      const response = await apiClient.get('/ai/agents', {
        params: { per_page: 100, ...(scope ? { scope } : {}), ...(search ? { search } : {}) },
      });
      const raw = response.data?.data;
      const items = (raw?.items ?? raw?.agents ?? []) as AgentListItem[];
      return items
        .map((a) => ({ id: a.id, name: a.name, agent_type: a.agent_type }))
        .sort((a, b) => a.name.localeCompare(b.name)) as AgentOption[];
    },
  });
}
