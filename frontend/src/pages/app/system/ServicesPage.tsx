import React from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { ServicesConfiguration } from '@/features/admin/components/settings/ServicesConfiguration';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';

export const ServicesPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  usePageWebSocket({ pageType: 'system' });

  // Check if user has services management permission
  const canManageServices = hasPermissions(user, ['admin.settings.update']);
  
  // Redirect if user doesn't have permission
  if (!canManageServices) {
    return <Navigate to="/app" replace />;
  }

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'System', icon: '⚙️' },
    { label: 'Services', icon: '🌐' }
  ];

  return (
    <PageContainer
      title="Services"
      description="Configure service routing, load balancing, and discovery settings"
      breadcrumbs={getBreadcrumbs()}
    >
      <div className="bg-theme-surface rounded-lg border border-theme">
        <div className="p-6">
          <ServicesConfiguration />
        </div>
      </div>
    </PageContainer>
  );
};

export default ServicesPage;