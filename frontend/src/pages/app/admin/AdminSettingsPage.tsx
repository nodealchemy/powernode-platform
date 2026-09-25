// Main Admin Settings Page with Tabbed Interface
import React from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { AdminSettingsTabs } from '@/features/admin/components/settings/AdminSettingsTabs';
import {
  ADMIN_SETTINGS_BASE,
  CORE_ADMIN_SETTINGS_TABS,
  CoreAdminSettingsTabId,
  findActiveSettingsTab,
  toAdminSettingsTab,
  useRegisteredSettingsTabs,
} from '@/features/admin/components/settings/adminSettingsTabList';

// Import all admin settings tab pages
import { AdminSettingsOverviewPage } from './AdminSettingsOverviewPage';
import { AdminSettingsEmailTabPage } from './AdminSettingsEmailTabPage';
import { AdminSettingsSecurityTabPage } from './AdminSettingsSecurityTabPage';
import AdminSettingsRateLimitingTabPage from './AdminSettingsRateLimitingTabPage';
import { AdminSettingsInfrastructureTabPage } from './AdminSettingsInfrastructureTabPage';
import { AdminSettingsVaultTabPage } from './AdminSettingsVaultTabPage';
import { AdminSettingsProxyTabPage } from './AdminSettingsProxyTabPage';
import { AdminSettingsAutonomyTabPage } from './AdminSettingsAutonomyTabPage';
import { AdminSettingsExtensionsTabPage } from './AdminSettingsExtensionsTabPage';

// The page each core tab renders. Keyed by the tab list's ids, so a tab
// without a page (or a page without a tab) does not compile.
const CORE_TAB_PAGES: Record<CoreAdminSettingsTabId, React.ComponentType> = {
  overview: AdminSettingsOverviewPage,
  extensions: AdminSettingsExtensionsTabPage,
  email: AdminSettingsEmailTabPage,
  proxy: AdminSettingsProxyTabPage,
  security: AdminSettingsSecurityTabPage,
  'rate-limiting': AdminSettingsRateLimitingTabPage,
  infrastructure: AdminSettingsInfrastructureTabPage,
  vault: AdminSettingsVaultTabPage,
  autonomy: AdminSettingsAutonomyTabPage,
};

// A tab href relative to the settings base, as a nested route path.
const relativeRoute = (href: string) =>
  href.startsWith(ADMIN_SETTINGS_BASE) ? href.slice(ADMIN_SETTINGS_BASE.length) || '/' : href;

export const AdminSettingsPage: React.FC = () => {
  const location = useLocation();
  const { user } = useSelector((state: RootState) => state.auth);

  // Extension-contributed tabs (e.g. business Payment Gateways) rendered inside
  // this tabbed shell. Keyed by namespace in the registry — core names none.
  const extensionTabs = useRegisteredSettingsTabs();

  // Check if user has admin settings permission
  const canAccessAdminSettings = hasPermissions(user, ['admin.settings.read']);

  // Redirect if user doesn't have permission
  if (!canAccessAdminSettings) {
    return <Navigate to="/app" replace />;
  }

  const allTabs = [...CORE_ADMIN_SETTINGS_TABS, ...extensionTabs.map(toAdminSettingsTab)];

  const getBreadcrumbs = () => {
    const activeTab = findActiveSettingsTab(allTabs, location.pathname);
    const breadcrumbs: { label: string; href?: string }[] = [
      { label: 'Dashboard', href: '/app' },
      { label: 'Admin', href: ADMIN_SETTINGS_BASE },
      { label: 'Settings', href: ADMIN_SETTINGS_BASE }
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
          {CORE_ADMIN_SETTINGS_TABS.map((tab) => {
            const TabPage = CORE_TAB_PAGES[tab.id];
            return <Route key={tab.id} path={relativeRoute(tab.href)} element={<TabPage />} />;
          })}

          {/* Extension-registered tabs, rendered inside this tabbed shell. */}
          {extensionTabs.map((tab) => {
            const TabComponent = tab.component;
            return <Route key={tab.id} path={relativeRoute(tab.path)} element={<TabComponent />} />;
          })}

          <Route
            path="*"
            element={<p className="text-theme-secondary">This settings tab does not exist.</p>}
          />
        </Routes>
      </div>
    </PageContainer>
  );
};

// No default export - use named export only
