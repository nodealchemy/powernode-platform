import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { SubscriptionsList } from '@/features/marketplace/components/SubscriptionsList';
import { RefreshCw, Store } from 'lucide-react';
import { useNotifications } from '@/shared/hooks/useNotifications';

export const SubscriptionsPage: React.FC = () => {
  const navigate = useNavigate();
  const { addNotification } = useNotifications();
  const [refreshKey, setRefreshKey] = useState(0);

  const handleSubscriptionAction = (action: string, subscriptionId: string) => {
    switch (action) {
      case 'view-usage':
        // Navigate to analytics with subscription filter for usage data
        navigate(`/app/business/analytics?subscription=${subscriptionId}&view=usage`);
        break;
      case 'view-analytics':
        // Navigate to analytics with subscription filter
        navigate(`/app/business/analytics?subscription=${subscriptionId}`);
        break;
      case 'configure':
        // Navigate to subscription settings
        addNotification({
          type: 'info',
          message: 'Opening subscription settings...'
        });
        navigate(`/app/marketplace/subscriptions/${subscriptionId}/settings`);
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