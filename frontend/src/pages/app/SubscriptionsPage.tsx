import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { SubscriptionsList } from '@/features/marketplace/components/SubscriptionsList';
import { RefreshCw, Store } from 'lucide-react';

export const SubscriptionsPage: React.FC = () => {
SubscriptionsPage.displayName = 'SubscriptionsPage';
  const navigate = useNavigate();
  const [refreshKey, setRefreshKey] = useState(0);

  const handleSubscriptionAction = (action: string, subscriptionId: string) => {
    
    switch (action) {
      case 'view-usage':
        // TODO: Navigate to usage details or show modal
        break;
      case 'view-analytics':
        // TODO: Navigate to analytics details or show modal
        break;
      case 'configure':
        // TODO: Show configuration modal
        break;
      default:
        // Refresh list for other actions (pause, resume, cancel, etc.)
        setRefreshKey(prev => prev + 1);
        break;
    }
  };

  const handleRefresh = () => {
    setRefreshKey(prev => prev + 1);
  };

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Subscriptions', icon: '📱' }
  ];

  const getPageActions = () => [
    {
      id: 'browse-marketplace',
      label: 'Browse Marketplace',
      onClick: () => navigate('/app/marketplace'),
      variant: 'primary' as const,
      icon: Store
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'secondary' as const,
      icon: RefreshCw
    }
  ];

  return (
    <PageContainer
      title="App Subscriptions"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      <div className="space-y-6">
        <div className="text-center sm:text-left">
          <p className="text-theme-secondary">
            Manage your app subscriptions, monitor usage, and control billing settings.
          </p>
        </div>

        <SubscriptionsList
          key={refreshKey}
          onSubscriptionAction={handleSubscriptionAction}
        />
      </div>
    </PageContainer>
  );
};