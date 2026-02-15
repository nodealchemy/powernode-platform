import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { CampaignDashboard } from '@/features/marketing/components/CampaignDashboard';
import { CampaignEditor } from '@/features/marketing/components/CampaignEditor';
import { campaignsApi } from '@/features/marketing/services/campaignsApi';
import { logger } from '@/shared/utils/logger';
import type { CampaignFormData } from '@/features/marketing/types';

export const MarketingCampaignsPage: React.FC = () => {
  const navigate = useNavigate();
  const [showEditor, setShowEditor] = useState(false);

  const handleSave = async (data: CampaignFormData) => {
    try {
      const campaign = await campaignsApi.create(data);
      setShowEditor(false);
      navigate(`/app/marketing/campaigns/${campaign.id}`);
    } catch (err) {
      logger.error('Failed to create campaign:', err);
    }
  };

  const pageActions: PageAction[] = [
    {
      id: 'create-campaign',
      label: 'New Campaign',
      onClick: () => setShowEditor(!showEditor),
      variant: 'primary',
      icon: Plus,
    },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Marketing', href: '/app/marketing/campaigns' },
    { label: 'Campaigns' },
  ];

  return (
    <PageContainer
      title="Campaigns"
      description="Create and manage marketing campaigns across channels."
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      {showEditor && (
        <CampaignEditor
          onSave={handleSave}
          onCancel={() => setShowEditor(false)}
        />
      )}
      <CampaignDashboard />
    </PageContainer>
  );
};
