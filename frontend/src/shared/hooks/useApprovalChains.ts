import { useState, useEffect, useCallback } from 'react';
import apiClient from '@/shared/services/apiClient';
import type { ApprovalChain, ApprovalChainStep } from '@/shared/types/approval';
import { logger } from '@/shared/utils/logger';

const CHAIN_API = '/ai/approval_chains';

export interface ChainCreatePayload {
  name: string;
  description?: string;
  is_sequential?: boolean;
  timeout_hours?: number;
  timeout_action?: 'approve' | 'reject' | 'escalate';
  steps: ApprovalChainStep[];
}

/**
 * CRUD hook for `Ai::ApprovalChain` records. Used by the System Settings
 * Approval Chains tab and (eventually) any other extension that needs
 * multi-step approval flows.
 */
export function useApprovalChains() {
  const [chains, setChains] = useState<ApprovalChain[]>([]);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(() => {
    setLoading(true);
    apiClient
      .get(CHAIN_API)
      .then((res) => setChains(res.data?.data || []))
      .catch((err) => logger.error('Failed to load approval chains', err))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    reload();
  }, [reload]);

  const create = useCallback(
    async (payload: ChainCreatePayload): Promise<ApprovalChain> => {
      const res = await apiClient.post(CHAIN_API, { approval_chain: payload });
      const chain = res.data?.data as ApprovalChain;
      setChains((prev) => [...prev, chain]);
      return chain;
    },
    []
  );

  const update = useCallback(
    async (id: string, payload: Partial<ChainCreatePayload>): Promise<ApprovalChain> => {
      const res = await apiClient.patch(`${CHAIN_API}/${id}`, { approval_chain: payload });
      const updated = res.data?.data as ApprovalChain;
      setChains((prev) => prev.map((c) => (c.id === id ? updated : c)));
      return updated;
    },
    []
  );

  const remove = useCallback(async (id: string) => {
    await apiClient.delete(`${CHAIN_API}/${id}`);
    setChains((prev) => prev.filter((c) => c.id !== id));
  }, []);

  const get = useCallback(async (id: string): Promise<ApprovalChain> => {
    const res = await apiClient.get(`${CHAIN_API}/${id}`);
    return res.data?.data as ApprovalChain;
  }, []);

  return { chains, loading, reload, create, update, delete: remove, get };
}
