import { useState, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { campaignsApi } from '../api/campaignsApi';
import type { CampaignProposal } from '../types/campaign';

// The discovery/delegation control plane's proposal queue. Mirrors the useCampaigns
// pattern (Redux auth + manual fetch state) — reuses the ai.campaigns.{read,manage} gate.
export function useProposals() {
  const { user } = useSelector((state: RootState) => state.auth);
  const [proposals, setProposals] = useState<CampaignProposal[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hasReadPermission = user?.permissions?.includes('ai.campaigns.read') ?? false;
  const hasManagePermission = user?.permissions?.includes('ai.campaigns.manage') ?? false;

  const fetchProposals = useCallback(async (params?: { status?: string }) => {
    setLoading(true);
    setError(null);
    try {
      const response = await campaignsApi.getProposals(params);
      setProposals(response.data?.proposals || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch proposals');
    } finally {
      setLoading(false);
    }
  }, []);

  const queueProposal = useCallback(async (id: string) => {
    await campaignsApi.queueProposal(id);
    await fetchProposals();
  }, [fetchProposals]);

  const approveProposal = useCallback(async (id: string) => {
    await campaignsApi.approveProposal(id);
    await fetchProposals();
  }, [fetchProposals]);

  const rejectProposal = useCallback(async (id: string, reason?: string) => {
    await campaignsApi.rejectProposal(id, reason);
    await fetchProposals();
  }, [fetchProposals]);

  // Spawns the campaign + dev-loop; returns the spawned campaign id (for opening detail).
  const spawnProposal = useCallback(async (id: string) => {
    const response = await campaignsApi.spawnProposal(id);
    await fetchProposals();
    return response.data?.spawned_campaign_id ?? response.data?.spawned_campaign?.id ?? null;
  }, [fetchProposals]);

  return {
    proposals,
    loading,
    error,
    hasReadPermission,
    hasManagePermission,
    fetchProposals,
    queueProposal,
    approveProposal,
    rejectProposal,
    spawnProposal,
  };
}
