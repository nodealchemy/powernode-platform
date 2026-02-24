import React, { useState } from 'react';
import { Plus } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { EmailListManager } from '../components/EmailListManager';

export const MarketingEmailListsPage: React.FC = () => {
  const [showCreateTrigger, setShowCreateTrigger] = useState(0);

  const pageActions: PageAction[] = [
    {
      id: 'create-list',
      label: 'New List',
      onClick: () => setShowCreateTrigger(prev => prev + 1),
      variant: 'primary',
      icon: Plus,
    },
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Marketing', href: '/app/marketing/campaigns' },
    { label: 'Email Lists' },
  ];

  return (
    <PageContainer
      title="Email Lists"
      description="Manage email lists and subscriber data."
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <EmailListManager key={showCreateTrigger} />
    </PageContainer>
  );
};
