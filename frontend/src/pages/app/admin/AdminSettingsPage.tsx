// Main Admin Settings Page with Tabbed Interface
import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AdminSettingsTabs } from '@/features/admin/components/settings/AdminSettingsTabs';

// Import all admin settings tab pages
import { AdminSettingsOverviewTabPage } from './AdminSettingsOverviewTabPage';
import { AdminSettingsPaymentGatewaysTabPage } from './AdminSettingsPaymentGatewaysTabPage';
import { AdminSettingsEmailTabPage } from './AdminSettingsEmailTabPage';
import { AdminSettingsSecurityTabPage } from './AdminSettingsSecurityTabPage';
import AdminSettingsRateLimitingTabPage from './AdminSettingsRateLimitingTabPage';
import { AdminSettingsPerformanceTabPage } from './AdminSettingsPerformanceTabPage';

export const AdminSettingsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  
  // Check if user has admin settings permission
  const canAccessAdminSettings = hasPermissions(user, ['admin.settings.read']);
  
  // Redirect if user doesn't have permission
  if (!canAccessAdminSettings) {
    return <Navigate to="/app" replace />;
  }

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Admin', icon: '🔧' },
    { label: 'Settings', icon: '⚙️' }
  ];

  return (
    <PageContainer
      title="Admin Settings"
      description="System administration and configuration"
      breadcrumbs={getBreadcrumbs()}
    >
      {/* Tabbed Interface */}
      <AdminSettingsTabs />

      {/* Tab Content */}
      <div className="mt-6">
        <Routes>
          {/* Default - Admin Settings Overview */}
          <Route path="/" element={<AdminSettingsOverviewTabPage />} />
          <Route path="/overview" element={<Navigate to="/app/admin/settings" replace />} />
          
          {/* Admin Settings Tabs */}
          <Route path="/payment-gateways" element={<AdminSettingsPaymentGatewaysTabPage />} />
          <Route path="/email" element={<AdminSettingsEmailTabPage />} />
          <Route path="/security" element={<AdminSettingsSecurityTabPage />} />
          <Route path="/rate-limiting" element={<AdminSettingsRateLimitingTabPage />} />
          <Route path="/performance" element={<AdminSettingsPerformanceTabPage />} />
          
          {/* Legacy redirects */}
          <Route path="/admin/*" element={<Navigate to="/app/admin/settings" replace />} />
          
          {/* Catch all - redirect to overview */}
          <Route path="*" element={<Navigate to="/app/admin/settings" replace />} />
        </Routes>
      </div>
    </PageContainer>
  );
};

// No default export - use named export only