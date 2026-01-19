// Main Admin Settings Page with Tabbed Interface
import React from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AdminSettingsTabs } from '@/features/admin/components/settings/AdminSettingsTabs';

// Import all admin settings tab pages
import { AdminSettingsOverviewTabPage } from './AdminSettingsOverviewTabPage';
import { AdminSettingsPaymentGatewaysTabPage } from './AdminSettingsPaymentGatewaysTabPage';
import { AdminSettingsEmailTabPage } from './AdminSettingsEmailTabPage';
import { AdminSettingsSecurityTabPage } from './AdminSettingsSecurityTabPage';
import AdminSettingsRateLimitingTabPage from './AdminSettingsRateLimitingTabPage';
import { AdminSettingsPerformanceTabPage } from './AdminSettingsPerformanceTabPage';
import { AdminSettingsProxyTabPage } from './AdminSettingsProxyTabPage';

// Tab definitions for breadcrumbs
const settingsTabs = [
  { id: 'overview', label: 'Overview', path: '/app/admin/settings', icon: '📊' },
  { id: 'payment-gateways', label: 'Payment Gateways', path: '/app/admin/settings/payment-gateways', icon: '💳' },
  { id: 'email', label: 'Email Settings', path: '/app/admin/settings/email', icon: '📧' },
  { id: 'proxy', label: 'Reverse Proxy', path: '/app/admin/settings/proxy', icon: '🌐' },
  { id: 'security', label: 'Security', path: '/app/admin/settings/security', icon: '🔒' },
  { id: 'rate-limiting', label: 'Rate Limiting', path: '/app/admin/settings/rate-limiting', icon: '🛡️' },
  { id: 'performance', label: 'Performance', path: '/app/admin/settings/performance', icon: '⚡' }
];

export const AdminSettingsPage: React.FC = () => {
  const location = useLocation();
  const { user } = useSelector((state: RootState) => state.auth);

  // WebSocket for real-time updates
  const { isConnected: _wsConnected } = usePageWebSocket({
    pageType: 'admin',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  // Check if user has admin settings permission
  const canAccessAdminSettings = hasPermissions(user, ['admin.settings.read']);

  // Redirect if user doesn't have permission
  if (!canAccessAdminSettings) {
    return <Navigate to="/app" replace />;
  }

  // Get active tab from current path
  const getActiveTab = () => {
    const currentPath = location.pathname;
    return settingsTabs.find(tab =>
      tab.path === currentPath || (currentPath.startsWith(tab.path) && tab.path !== '/app/admin/settings')
    ) || settingsTabs[0];
  };

  const getBreadcrumbs = () => {
    const activeTab = getActiveTab();
    const breadcrumbs: { label: string; href?: string; icon: string }[] = [
      { label: 'Dashboard', href: '/app', icon: '🏠' },
      { label: 'Admin', href: '/app/admin', icon: '🔧' },
      { label: 'Settings', href: '/app/admin/settings', icon: '⚙️' }
    ];

    // Add active tab if not on overview
    if (activeTab && activeTab.id !== 'overview') {
      breadcrumbs.push({ label: activeTab.label, icon: activeTab.icon });
    }

    return breadcrumbs;
  };

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
          <Route path="/proxy" element={<AdminSettingsProxyTabPage />} />
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