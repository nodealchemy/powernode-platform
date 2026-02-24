import React from 'react';
import { useParams } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { CampaignDetail } from '../components/CampaignDetail';

export const MarketingCampaignDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Marketing', href: '/app/marketing/campaigns' },
    { label: 'Campaigns', href: '/app/marketing/campaigns' },
    { label: 'Campaign Detail' },
  ];

  return (
    <PageContainer
      title="Campaign Detail"
      breadcrumbs={breadcrumbs}
    >
      {id ? (
        <CampaignDetail campaignId={id} />
      ) : (
        <div className="card-theme p-6 text-center">
          <p className="text-theme-error">Campaign ID is required.</p>
        </div>
      )}
    </PageContainer>
  );
};
