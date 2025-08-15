import React from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { hasAdminAccess } from '../../utils/permissionUtils';
import { PageBreadcrumb } from '../../components/layout/PageBreadcrumb';
import { TabNavigation, MobileTabNavigation } from '../../components/ui/TabNavigation';

// Import individual tab pages
import { AdminSettingsOverviewTabPage } from './AdminSettingsOverviewTabPage';
import { AdminSettingsPlatformTabPage } from './AdminSettingsPlatformTabPage';
import { AdminSettingsEmailTabPage } from './AdminSettingsEmailTabPage';
import { AdminSettingsMaintenanceTabPage } from './AdminSettingsMaintenanceTabPage';
import { AdminSettingsSecurityTabPage } from './AdminSettingsSecurityTabPage';
import { AdminSettingsPerformanceTabPage } from './AdminSettingsPerformanceTabPage';
import { AdminSettingsPaymentGatewaysTabPage } from './AdminSettingsPaymentGatewaysTabPage';
import { AdminSettingsWebhooksTabPage } from './AdminSettingsWebhooksTabPage';

interface TabConfig {
  id: string;
  label: string;
  icon: string;
  path: string;
}

const tabs: TabConfig[] = [
  { id: 'overview', label: 'Overview', icon: '📊', path: '/dashboard/admin_settings/overview' },
  { id: 'platform', label: 'Platform Config', icon: '⚙️', path: '/dashboard/admin_settings/platform' },
  { id: 'payment_gateways', label: 'Payment Gateways', icon: '💳', path: '/dashboard/admin_settings/payment_gateways' },
  { id: 'webhooks', label: 'Webhooks', icon: '🔗', path: '/dashboard/admin_settings/webhooks' },
  { id: 'email', label: 'Email Settings', icon: '📧', path: '/dashboard/admin_settings/email' },
  { id: 'maintenance', label: 'Maintenance', icon: '🔧', path: '/dashboard/admin_settings/maintenance' },
  { id: 'security', label: 'Security', icon: '🔒', path: '/dashboard/admin_settings/security' },
  { id: 'performance', label: 'Performance', icon: '🚀', path: '/dashboard/admin_settings/performance' },
];

export const AdminSettingsLayoutPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const isAdmin = hasAdminAccess(user);
  const location = useLocation();

  // Redirect non-admins to dashboard
  if (!isAdmin) {
    return <Navigate to="/dashboard" replace />;
  }

  // Determine active tab based on current path
  const getActiveTab = () => {
    const currentPath = location.pathname;
    const activeTab = tabs.find(tab => currentPath === tab.path || currentPath.startsWith(tab.path + '/'));
    return activeTab?.id || 'overview';
  };

  const activeTabId = getActiveTab();

  // Get current tab info for breadcrumbs
  const getCurrentTab = () => {
    return tabs.find(tab => tab.id === activeTabId) || tabs[0];
  };

  const currentTab = getCurrentTab();
  const breadcrumbItems = [
    { label: 'Dashboard', path: '/dashboard', icon: '🏠' },
    { label: 'Admin Settings', path: '/dashboard/admin_settings', icon: '🔧' },
    { label: currentTab.label, icon: currentTab.icon }
  ];

  return (
    <div className="space-y-6">
      {/* Breadcrumbs */}
      <div>
        <PageBreadcrumb items={breadcrumbItems} />
      </div>
      
      {/* Enhanced Header */}
      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 className="text-3xl font-bold text-theme-primary">Admin Settings</h1>
            <p className="text-theme-secondary mt-2">
              Configure platform settings, security, and system maintenance options.
            </p>
          </div>
        </div>
      </div>

      {/* Tab Navigation */}
      <div>
        <div className="hidden sm:block">
          <TabNavigation tabs={tabs} basePath="/dashboard/admin_settings" />
        </div>
        <MobileTabNavigation tabs={tabs} basePath="/dashboard/admin_settings" />
      </div>

      {/* Tab Content */}
      <div>
        <Routes>
        <Route index element={<Navigate to="overview" replace />} />
        <Route path="overview" element={<AdminSettingsOverviewTabPage />} />
        <Route path="platform" element={<AdminSettingsPlatformTabPage />} />
        <Route path="payment_gateways" element={<AdminSettingsPaymentGatewaysTabPage />} />
        <Route path="webhooks" element={<AdminSettingsWebhooksTabPage />} />
        <Route path="email" element={<AdminSettingsEmailTabPage />} />
        <Route path="maintenance" element={<AdminSettingsMaintenanceTabPage />} />
        <Route path="security" element={<AdminSettingsSecurityTabPage />} />
        <Route path="performance" element={<AdminSettingsPerformanceTabPage />} />
        <Route path="*" element={<Navigate to="overview" replace />} />
        </Routes>
      </div>
    </div>
  );
};

export default AdminSettingsLayoutPage;