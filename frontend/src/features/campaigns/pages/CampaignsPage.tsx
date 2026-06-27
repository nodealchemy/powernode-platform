import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Plus } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { useCampaigns } from '../hooks/useCampaigns';
import { CampaignsIndexTable } from '../components/CampaignsIndexTable';
import { NewCampaignModal } from '../components/NewCampaignModal';
import { CampaignDetailModal } from '../components/CampaignDetailModal';
import type { CreateCampaignParams } from '../types/campaign';

export const CampaignsContent: React.FC<{
  onActionsReady?: (actions: PageAction[]) => void;
}> = ({ onActionsReady }) => {
  const {
    campaigns,
    loading,
    error,
    hasReadPermission,
    hasManagePermission,
    fetchCampaigns,
    createCampaign,
  } = useCampaigns();

  const [showNew, setShowNew] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    if (hasReadPermission) fetchCampaigns();
  }, [hasReadPermission, fetchCampaigns]);

  const actions = useMemo<PageAction[]>(() => {
    if (!hasManagePermission) return [];
    return [{
      id: 'new-campaign',
      label: 'New Campaign',
      onClick: () => setShowNew(true),
      variant: 'primary',
      icon: Plus,
    }];
  }, [hasManagePermission]);

  useEffect(() => {
    if (onActionsReady) onActionsReady(actions);
  }, [actions, onActionsReady]);

  const handleCreate = useCallback(async (data: CreateCampaignParams) => {
    const created = await createCampaign(data);
    setShowNew(false);
    if (created?.id) setSelectedId(created.id);
  }, [createCampaign]);

  if (!hasReadPermission) {
    return (
      <div className="py-12 text-center text-theme-secondary">
        You do not have permission to view improvement campaigns.
      </div>
    );
  }

  return (
    <>
      {error && <div className="mb-4"><ErrorAlert message={error} /></div>}

      <CampaignsIndexTable
        campaigns={campaigns}
        loading={loading}
        canManage={hasManagePermission}
        onSelect={setSelectedId}
        onNewCampaign={() => setShowNew(true)}
      />

      <NewCampaignModal
        isOpen={showNew}
        onClose={() => setShowNew(false)}
        onCreate={handleCreate}
      />

      <CampaignDetailModal
        campaignId={selectedId}
        isOpen={selectedId !== null}
        onClose={() => setSelectedId(null)}
        canManage={hasManagePermission}
        onChanged={() => fetchCampaigns()}
      />
    </>
  );
};
