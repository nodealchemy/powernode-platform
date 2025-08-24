import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AppsList, CreateAppModal } from '@/features/marketplace';
import { App } from '@/features/marketplace/types';
import { RefreshCw, Plus } from 'lucide-react';

export const AppsPage: React.FC = () => {
AppsPage.displayName = 'AppsPage';
  const navigate = useNavigate();
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Apps', icon: '📱' }
  ];

  const getPageActions = () => [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: () => setRefreshKey(prev => prev + 1),
      variant: 'secondary' as const,
      icon: RefreshCw
    },
    {
      id: 'create-app',
      label: 'Create App',
      onClick: () => setShowCreateModal(true),
      variant: 'primary' as const,
      icon: Plus,
      permission: 'apps.create'
    }
  ];

  const handleCreateApp = () => {
    setShowCreateModal(true);
  };

  const handleEditApp = (app: App) => {
    navigate(`/app/marketplace/apps/${app.id}/edit`);
  };

  const handleViewApp = (app: App) => {
    navigate(`/app/marketplace/apps/${app.id}`);
  };

  const handleCreateSuccess = (app: App) => {
    setRefreshKey(prev => prev + 1);
    navigate(`/app/marketplace/apps/${app.id}`);
  };

  return (
    <>
      <PageContainer
        title="Apps"
        breadcrumbs={getBreadcrumbs()}
        actions={getPageActions()}
      >
        <div className="space-y-6">
          <div className="bg-theme-background border border-theme rounded-lg p-6">
            <div className="flex items-start gap-4">
              <div className="w-12 h-12 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white text-xl">
                📱
              </div>
              <div>
                <h2 className="text-lg font-semibold text-theme-primary mb-2">
                  Manage Your Apps
                </h2>
                <p className="text-theme-secondary mb-4">
                  Create, configure, and publish apps on the marketplace. Define features, 
                  set up pricing plans, and manage subscriptions.
                </p>
                <div className="flex flex-wrap gap-4 text-sm text-theme-secondary">
                  <span className="flex items-center gap-1">
                    <span className="w-2 h-2 bg-theme-success rounded-full"></span>
                    Published apps appear in the marketplace
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="w-2 h-2 bg-theme-warning rounded-full"></span>
                    Draft apps can be edited and configured
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="w-2 h-2 bg-theme-info rounded-full"></span>
                    Apps under review are being evaluated
                  </span>
                </div>
              </div>
            </div>
          </div>

          <AppsList
            key={refreshKey}
            onCreateApp={handleCreateApp}
            onEditApp={handleEditApp}
            onViewApp={handleViewApp}
            showCreateButton={true}
          />
        </div>
      </PageContainer>

      <CreateAppModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSuccess={handleCreateSuccess}
      />
    </>
  );
};