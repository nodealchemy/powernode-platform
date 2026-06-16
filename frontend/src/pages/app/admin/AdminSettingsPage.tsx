// Main Admin Settings Page with Tabbed Interface
import React from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AdminSettingsTabs } from '@/features/admin/components/settings/AdminSettingsTabs';
import { featureRegistry } from '@/shared/services/featureRegistry';

// Import all admin settings tab pages
import { AdminSettingsOverviewTabPage } from './AdminSettingsOverviewTabPage';
import { AdminSettingsEmailTabPage } from './AdminSettingsEmailTabPage';
import { AdminSettingsSecurityTabPage } from './AdminSettingsSecurityTabPage';
import AdminSettingsRateLimitingTabPage from './AdminSettingsRateLimitingTabPage';
import { AdminSettingsInfrastructureTabPage } from './AdminSettingsInfrastructureTabPage';
import { AdminSettingsVaultTabPage } from './AdminSettingsVaultTabPage';
import { AdminSettingsProxyTabPage } from './AdminSettingsProxyTabPage';
import { AdminSettingsDevelopmentTabPage } from './AdminSettingsDevelopmentTabPage';
import { AdminSettingsExtensionsTabPage } from './AdminSettingsExtensionsTabPage';

const SETTINGS_BASE = '/app/admin/settings';

// Core tab definitions for breadcrumbs. Extension-owned tabs (e.g. Payment
// Gateways) are merged in at render time from featureRegistry.getSettingsTabs().
const settingsTabs = [
  { id: 'overview', label: 'Overview', path: '/app/admin/settings', icon: '📊' },
  { id: 'extensions', label: 'Extensions', path: '/app/admin/settings/extensions', icon: '🧩' },
  { id: 'email', label: 'Email Settings', path: '/app/admin/settings/email', icon: '📧' },
  { id: 'proxy', label: 'Reverse Proxy', path: '/app/admin/settings/proxy', icon: '🌐' },
  { id: 'security', label: 'Security', path: '/app/admin/settings/security', icon: '🔒' },
  { id: 'rate-limiting', label: 'Rate Limiting', path: '/app/admin/settings/rate-limiting', icon: '🛡️' },
  { id: 'infrastructure', label: 'Infrastructure', path: '/app/admin/settings/infrastructure', icon: '🖥️' },
  { id: 'vault', label: 'Vault & Secrets', path: '/app/admin/settings/vault', icon: '🔑' },
  { id: 'development', label: 'Development', path: '/app/admin/settings/development', icon: '🔧' }
];

export const AdminSettingsPage: React.FC = () => {
  const location = useLocation();
  const { user } = useSelector((state: RootState) => state.auth);

  // Re-render when an extension registers a settings tab (registration happens
  // at module import time, but subscribing keeps this robust to later changes).
  const [, setRegistryVersion] = React.useState(() => featureRegistry.getVersion());
  React.useEffect(() => {
    return featureRegistry.subscribe(() => setRegistryVersion(featureRegistry.getVersion()));
  }, []);

  // Extension-contributed tabs (e.g. business Payment Gateways) rendered inside
  // this tabbed shell. Keyed by namespace in the registry — core names none.
  const extensionTabs = featureRegistry.getSettingsTabs();

  // WebSocket for real-time updates
  usePageWebSocket({
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

  // Core tabs plus extension-registered tabs, for active-tab/breadcrumb lookup.
  const allTabs = [
    ...settingsTabs,
    ...extensionTabs.map(tab => ({ id: tab.id, label: tab.label, path: tab.path, icon: tab.icon })),
  ];

  // Get active tab from current path
  const getActiveTab = () => {
    const currentPath = location.pathname;
    return allTabs.find(tab =>
      tab.path === currentPath || (currentPath.startsWith(tab.path) && tab.path !== '/app/admin/settings')
    ) || allTabs[0];
  };

  const getBreadcrumbs = () => {
    const activeTab = getActiveTab();
    const breadcrumbs: { label: string; href?: string }[] = [
      { label: 'Dashboard', href: '/app' },
      { label: 'Admin', href: '/app/admin' },
      { label: 'Settings', href: '/app/admin/settings' }
    ];

    // Add active tab if not on overview
    if (activeTab && activeTab.id !== 'overview') {
      breadcrumbs.push({ label: activeTab.label });
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
          <Route path="/extensions" element={<AdminSettingsExtensionsTabPage />} />
          <Route path="/email" element={<AdminSettingsEmailTabPage />} />
          <Route path="/proxy" element={<AdminSettingsProxyTabPage />} />
          <Route path="/security" element={<AdminSettingsSecurityTabPage />} />
          <Route path="/rate-limiting" element={<AdminSettingsRateLimitingTabPage />} />
          <Route path="/infrastructure" element={<AdminSettingsInfrastructureTabPage />} />
          <Route path="/vault" element={<AdminSettingsVaultTabPage />} />
          <Route path="/performance" element={<Navigate to="/app/admin/settings/infrastructure" replace />} />
          <Route path="/development" element={<AdminSettingsDevelopmentTabPage />} />

          {/* Extension-registered tabs (e.g. business Payment Gateways),
              rendered inside this tabbed shell. Path is full; strip the base
              to get the route relative to /app/admin/settings. */}
          {extensionTabs.map((tab) => {
            const TabComponent = tab.component;
            const relativePath = tab.path.startsWith(SETTINGS_BASE)
              ? tab.path.slice(SETTINGS_BASE.length) || '/'
              : tab.path;
            return (
              <Route
                key={tab.id}
                path={relativePath}
                element={<TabComponent />}
              />
            );
          })}

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