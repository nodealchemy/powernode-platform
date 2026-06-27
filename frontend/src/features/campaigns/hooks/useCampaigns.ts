import { useState, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { campaignsApi } from '../api/campaignsApi';
import type { CampaignSummary, CreateCampaignParams } from '../types/campaign';

export function useCampaigns() {
  const { user } = useSelector((state: RootState) => state.auth);
  const [campaigns, setCampaigns] = useState<CampaignSummary[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hasReadPermission = user?.permissions?.includes('ai.campaigns.read') ?? false;
  const hasManagePermission = user?.permissions?.includes('ai.campaigns.manage') ?? false;

  const fetchCampaigns = useCallback(async (params?: { status?: string }) => {
    setLoading(true);
    setError(null);
    try {
      const response = await campaignsApi.getCampaigns(params);
      setCampaigns(response.data?.campaigns || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch campaigns');
    } finally {
      setLoading(false);
    }
  }, []);

  const createCampaign = useCallback(async (data: CreateCampaignParams) => {
    const response = await campaignsApi.createCampaign(data);
    const created = response.data;
    if (created) {
      setCampaigns(prev => [created, ...prev]);
    }
    return created;
  }, []);

  const stopCampaign = useCallback(async (id: string, summary?: string) => {
    await campaignsApi.stopCampaign(id, summary);
    await fetchCampaigns();
  }, [fetchCampaigns]);

  return {
    campaigns,
    loading,
    error,
    hasReadPermission,
    hasManagePermission,
    fetchCampaigns,
    createCampaign,
    stopCampaign,
  };
}
