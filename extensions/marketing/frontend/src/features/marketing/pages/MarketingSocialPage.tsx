import React, { useState } from 'react';
import { Plus } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { SocialMediaManager } from '../components/SocialMediaManager';

export const MarketingSocialPage: React.FC = () => {
  const [showConnectTrigger, setShowConnectTrigger] = useState(0);

  const pageActions: PageAction[] = [
    {
      id: 'connect-account',
      label: 'Connect Account',
      onClick: () => setShowConnectTrigger(prev => prev + 1),
      variant: 'primary',
      icon: Plus,
    },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Marketing', href: '/app/marketing/campaigns' },
    { label: 'Social' },
  ];

  return (
    <PageContainer
      title="Social Media"
      description="Manage connected social media accounts and monitor engagement."
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <SocialMediaManager key={showConnectTrigger} />
    </PageContainer>
  );
};
