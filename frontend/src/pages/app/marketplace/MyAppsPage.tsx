import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AppsList } from '@/features/marketplace/components/apps/AppsList';
import { CreateAppModal } from '@/features/marketplace/components/apps/CreateAppModal';
import { useApps } from '@/features/marketplace/hooks/useApps';
import { App, AppFilters } from '@/features/marketplace/types';

export const MyAppsPage: React.FC = () => {
MyAppsPage.displayName = 'MyAppsPage';
  const navigate = useNavigate();
  const [filters] = useState<AppFilters>({ page: 1, per_page: 20 });
  const [showCreateModal, setShowCreateModal] = useState(false);

  const { 
    // apps, 
    // loading, 
    // error, 
    // pagination, 
    // createApp,
    refresh 
  } = useApps(filters);

  const handleCreateApp = () => {
    setShowCreateModal(true);
  };

  const handleAppCreated = (app: App) => {
    setShowCreateModal(false);
    refresh();
    // Navigate to the new app's management page
    navigate(`/app/marketplace/apps/${app.id}`);
  };

  const handleManageApp = (app: App) => {
    navigate(`/app/marketplace/apps/${app.id}`);
  };

  // const handleLoadMore = () => {
  //   if (pagination.current_page < pagination.total_pages) {
  //     setFilters(prev => ({ ...prev, page: prev.page! + 1 }));
  //   }
  // };

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Marketplace', href: '/app/marketplace', icon: '🏪' },
    { label: 'My Apps', icon: '📱' }
  ];

  const getPageActions = () => [
    {
      id: 'create-app',
      label: 'Create App',
      onClick: handleCreateApp,
      variant: 'primary' as const,
      icon: 'Plus',
      permission: 'apps.create'
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'secondary' as const,
      icon: 'RefreshCw'
    }
  ];

  return (
    <PageContainer
      title="My Apps"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      <div className="space-y-6">
        <AppsList
          onCreateApp={handleCreateApp}
          onViewApp={handleManageApp}
          filters={filters}
          showCreateButton={true}
        />

        {showCreateModal && (
          <CreateAppModal
            isOpen={showCreateModal}
            onClose={() => setShowCreateModal(false)}
            onSuccess={handleAppCreated}
          />
        )}
      </div>
    </PageContainer>
  );
};