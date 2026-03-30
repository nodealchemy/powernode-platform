import api from '@/shared/services/api';
import type {
  MemoryEntry,
  SharedKnowledgeEntry,
  MemoryStats,
  MemoryTier,
  MemoryPagination,
  PaginatedMemoryResponse,
  MemoryFilters,
} from '../types/memory';

const MEMORY_KEYS = {
  all: ['memory'] as const,
  stats: (agentId: string) => [...MEMORY_KEYS.all, 'stats', agentId] as const,
  entries: (agentId: string, tier: MemoryTier) => [...MEMORY_KEYS.all, 'entries', agentId, tier] as const,
  sharedKnowledge: () => [...MEMORY_KEYS.all, 'shared'] as const,
};

export { MEMORY_KEYS };

export async function fetchMemoryStats(agentId: string): Promise<MemoryStats> {
  const { data } = await api.get(`/ai/agents/${agentId}/tiered_memory/stats`);
  const result = data.data;
  // Ensure all tier keys exist with safe defaults
  const defaults: MemoryStats = {
    working: { count: 0 },
    short_term: { total: 0, active: 0, expired: 0 },
    long_term: { total: 0, active: 0 },
    shared: { total: 0, with_embedding: 0 },
  };
  const stats = result?.stats || result;
  return {
    working: stats?.working || defaults.working,
    short_term: stats?.short_term || defaults.short_term,
    long_term: stats?.long_term || defaults.long_term,
    shared: stats?.shared || defaults.shared,
  };
}

export async function fetchMemoryEntries(agentId: string, tier: MemoryTier): Promise<MemoryEntry[]> {
  const { data } = await api.get(`/ai/agents/${agentId}/tiered_memory`, { params: { tier } });
  const result = data.data;
  if (Array.isArray(result)) return result;
  if (result?.entries && Array.isArray(result.entries)) return result.entries;
  return [];
}

export async function fetchMemoryEntriesPaginated(
  agentId: string,
  tier: MemoryTier,
  page: number = 1,
  perPage: number = 25,
  filters: MemoryFilters = {}
): Promise<PaginatedMemoryResponse> {
  const params: Record<string, string | number> = { tier, page, per_page: perPage };
  if (filters.q) params.q = filters.q;
  if (filters.category) params.category = filters.category;
  if (filters.content_type) params.content_type = filters.content_type;
  if (filters.tag) params.tag = filters.tag;
  if (filters.min_importance !== undefined) params.min_importance = filters.min_importance;

  const { data } = await api.get(`/ai/agents/${agentId}/tiered_memory`, { params });
  const result = data.data;

  const defaultPagination: MemoryPagination = {
    current_page: page,
    per_page: perPage,
    total_pages: 1,
    total_count: 0,
    has_more: false,
  };

  // Handle both old (flat array) and new (paginated) response shapes
  if (Array.isArray(result)) {
    return { tier, entries: result, pagination: { ...defaultPagination, total_count: result.length } };
  }
  return {
    tier: result?.tier || tier,
    entries: result?.entries || [],
    pagination: result?.pagination || defaultPagination,
  };
}

export async function fetchSharedKnowledge(): Promise<SharedKnowledgeEntry[]> {
  const { data } = await api.get('/ai/memory/shared_knowledge');
  const result = data.data;
  if (Array.isArray(result)) return result;
  if (result?.entries && Array.isArray(result.entries)) return result.entries;
  if (result?.data && Array.isArray(result.data)) return result.data;
  return [];
}

export async function writeMemory(params: {
  agent_id: string;
  key: string;
  value: unknown;
  tier: MemoryTier;
  session_id?: string;
}): Promise<MemoryEntry> {
  const { data } = await api.post<{ data: MemoryEntry }>(`/ai/agents/${params.agent_id}/tiered_memory`, params);
  return data.data;
}

export async function deleteMemory(params: {
  agent_id: string;
  key: string;
  tier: MemoryTier;
  session_id?: string;
}): Promise<void> {
  await api.delete(`/ai/agents/${params.agent_id}/tiered_memory/${params.key}`, {
    params: { tier: params.tier, session_id: params.session_id },
  });
}
