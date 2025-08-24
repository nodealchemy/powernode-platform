import React from 'react';
import { Routes, Route, Navigate, useLocation, useNavigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RefreshCw } from 'lucide-react';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, MobileTabContainer } from '@/shared/components/ui/TabContainer';

// Import individual tab pages
import { AdminSettingsOverviewTabPage } from './AdminSettingsOverviewTabPage';
import { AdminSettingsPlatformTabPage } from './AdminSettingsPlatformTabPage';
import { AdminSettingsEmailTabPage } from './AdminSettingsEmailTabPage';
// import { AdminSettingsMaintenanceTabPage } from './AdminSettingsMaintenanceTabPage'; // File doesn't exist
import { AdminSettingsSecurityTabPage } from './AdminSettingsSecurityTabPage';
import { AdminSettingsPerformanceTabPage } from './AdminSettingsPerformanceTabPage';
import { AdminSettingsPaymentGatewaysTabPage } from './AdminSettingsPaymentGatewaysTabPage';

interface TabConfig {
  id: string;
  label: string;
  icon: string;
  path: string;
}

const tabs: TabConfig[] = [
  { id: 'overview', label: 'Overview', icon: '📊', path: '/app/admin_settings/overview' },
  { id: 'platform', label: 'Platform Config', icon: '⚙️', path: '/app/admin_settings/platform' },
  { id: 'payment_gateways', label: 'Payment Gateways', icon: '💳', path: '/app/admin_settings/payment_gateways' },
  { id: 'email', label: 'Email Settings', icon: '📧', path: '/app/admin_settings/email' },
  { id: 'maintenance', label: 'Maintenance', icon: '🔧', path: '/app/admin_settings/maintenance' },
  { id: 'security', label: 'Security', icon: '🔒', path: '/app/admin_settings/security' },
  { id: 'performance', label: 'Performance', icon: '🚀', path: '/app/admin_settings/performance' },
];

export const AdminSettingsLayoutPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const canAccessSettings = hasPermissions(user, ['admin.settings.view']);
  const location = useLocation();
  const navigate = useNavigate();

  // Redirect users without settings permissions to dashboard
  if (!canAccessSettings) {
    return <Navigate to="/app" replace />;
  }

  // Determine active tab based on current path
  const getActiveTab = () => {
    const currentPath = location.pathname;
    const activeTab = tabs.find(tab => currentPath === tab.path || currentPath.startsWith(tab.path + '/'));
    return activeTab?.id || 'overview';
  };

  const activeTabId = getActiveTab();

  const handleTabChange = (tabId: string) => {
    const tab = tabs.find(t => t.id === tabId);
    if (tab) {
      navigate(tab.path);
    }
  };

  // Get current tab info for breadcrumbs
  const getCurrentTab = () => {
    return tabs.find(tab => tab.id === activeTabId) || tabs[0];
  };

  const currentTab = getCurrentTab();

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Admin Settings', href: '/app/admin_settings', icon: '⚙️' },
    { label: currentTab.label, icon: currentTab.icon }
  ];

  const getPageActions = () => [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: () => window.location.reload(),
      variant: 'secondary' as const,
      icon: RefreshCw
    }
  ];

  return (
    <PageContainer
      title="Admin Settings"
      description="Configure platform settings, security, and system maintenance options."
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      {/* Tab Navigation */}
      <div className="hidden sm:block">
        <TabContainer
          tabs={tabs}
          activeTab={activeTabId}
          onTabChange={handleTabChange}
          basePath="/app/admin_settings"
          variant="underline"
          showContent={false}
        />
      </div>
      <div className="sm:hidden">
        <MobileTabContainer
          tabs={tabs}
          activeTab={activeTabId}
          onTabChange={handleTabChange}
          basePath="/app/admin_settings"
        />
      </div>

      {/* Tab Content */}
      <div className="mt-6">
        <Routes>
        <Route index element={<Navigate to="overview" replace />} />
        <Route path="overview" element={<AdminSettingsOverviewTabPage />} />
        <Route path="platform" element={<AdminSettingsPlatformTabPage />} />
        <Route path="payment_gateways" element={<AdminSettingsPaymentGatewaysTabPage />} />
        <Route path="email" element={<AdminSettingsEmailTabPage />} />
        {/* <Route path="maintenance" element={<AdminSettingsMaintenanceTabPage />} /> */}
        <Route path="security" element={<AdminSettingsSecurityTabPage />} />
        <Route path="performance" element={<AdminSettingsPerformanceTabPage />} />
        <Route path="*" element={<Navigate to="overview" replace />} />
        </Routes>
      </div>
    </PageContainer>
  );
};

export default AdminSettingsLayoutPage;