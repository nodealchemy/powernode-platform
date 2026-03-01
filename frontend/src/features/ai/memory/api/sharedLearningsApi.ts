import api from '@/shared/services/api';

export interface Learning {
  category: string;
  content: string;
  agent_id?: string;
  importance: number;
  recorded_at: string;
  promoted_from?: string;
  promoted_at?: string;
}

export const sharedLearningsApi = {
  async fetchGlobalLearnings(): Promise<Learning[]> {
    const response = await api.get('/ai/memory_pools', { params: { pool_type: 'global', scope: 'persistent' } });
    const pools = response.data.data || [];
    const globalPool = pools.find((p: Record<string, unknown>) => (p.name as string)?.includes('Global Learnings'));
    if (!globalPool) return [];
    const detail = await api.get(`/ai/memory_pools/${globalPool.id}`);
    return (detail.data.data?.data?.learnings as Learning[]) || [];
  },

  async fetchPoolLearnings(poolId: string): Promise<Learning[]> {
    const response = await api.get(`/ai/memory_pools/${poolId}`);
    return (response.data.data?.data?.learnings as Learning[]) || [];
  },
};
