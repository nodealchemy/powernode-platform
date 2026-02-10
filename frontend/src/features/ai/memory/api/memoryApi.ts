import api from '@/shared/services/api';
import type { MemoryEntry, SharedKnowledgeEntry, MemoryStats, MemoryTier } from '../types/memory';

const MEMORY_KEYS = {
  all: ['memory'] as const,
  stats: (agentId: string) => [...MEMORY_KEYS.all, 'stats', agentId] as const,
  entries: (agentId: string, tier: MemoryTier) => [...MEMORY_KEYS.all, 'entries', agentId, tier] as const,
  sharedKnowledge: () => [...MEMORY_KEYS.all, 'shared'] as const,
};

export { MEMORY_KEYS };

export async function fetchMemoryStats(agentId: string): Promise<MemoryStats> {
  const { data } = await api.get<{ data: MemoryStats }>(`/ai/agents/${agentId}/memory/stats`);
  return data.data;
}

export async function fetchMemoryEntries(agentId: string, tier: MemoryTier): Promise<MemoryEntry[]> {
  const { data } = await api.get<{ data: MemoryEntry[] }>(`/ai/agents/${agentId}/memory`, { params: { tier } });
  return data.data;
}

export async function fetchSharedKnowledge(): Promise<SharedKnowledgeEntry[]> {
  const { data } = await api.get<{ data: SharedKnowledgeEntry[] }>('/ai/memory/shared_knowledge');
  return data.data;
}

export async function writeMemory(params: {
  agent_id: string;
  key: string;
  value: unknown;
  tier: MemoryTier;
  session_id?: string;
}): Promise<MemoryEntry> {
  const { data } = await api.post<{ data: MemoryEntry }>(`/ai/agents/${params.agent_id}/memory`, params);
  return data.data;
}

export async function deleteMemory(params: {
  agent_id: string;
  key: string;
  tier: MemoryTier;
  session_id?: string;
}): Promise<void> {
  await api.delete(`/ai/agents/${params.agent_id}/memory/${params.key}`, {
    params: { tier: params.tier, session_id: params.session_id },
  });
}
