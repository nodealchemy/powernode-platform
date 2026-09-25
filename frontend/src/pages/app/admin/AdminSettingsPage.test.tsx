import { render, screen } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { AdminSettingsPage } from './AdminSettingsPage';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { CORE_ADMIN_SETTINGS_TABS } from '@/features/admin/components/settings/adminSettingsTabList';

// Mock hooks - hasPermissions checks user permissions
const mockHasPermissions = jest.fn();
jest.mock('@/shared/utils/permissionUtils', () => ({
  hasPermissions: (user: unknown, permissions: string[]) => mockHasPermissions(user, permissions)
}));

// Mock child components
jest.mock('@/features/admin/components/settings/AdminSettingsTabs', () => ({
  AdminSettingsTabs: () => (
    <div data-testid="admin-settings-tabs">
      <button>Overview</button>
      <button>Payment Gateways</button>
      <button>Email Settings</button>
      <button>Security</button>
    </div>
  )
}));

// Mock all admin settings tab pages
jest.mock('./AdminSettingsOverviewPage', () => ({
  AdminSettingsOverviewPage: () => <div data-testid="overview-tab-page">Overview Content</div>
}));

jest.mock('./AdminSettingsExtensionsTabPage', () => ({
  AdminSettingsExtensionsTabPage: () => <div data-testid="extensions-tab-page">Extensions Content</div>
}));

jest.mock('./AdminSettingsVaultTabPage', () => ({
  AdminSettingsVaultTabPage: () => <div data-testid="vault-tab-page">Vault Content</div>
}));

jest.mock('./AdminSettingsAutonomyTabPage', () => ({
  AdminSettingsAutonomyTabPage: () => <div data-testid="autonomy-tab-page">Autonomy Content</div>
}));

jest.mock('./AdminSettingsEmailTabPage', () => ({
  AdminSettingsEmailTabPage: () => <div data-testid="email-tab-page">Email Settings Content</div>
}));

jest.mock('./AdminSettingsSecurityTabPage', () => ({
  AdminSettingsSecurityTabPage: () => <div data-testid="security-tab-page">Security Content</div>
}));

jest.mock('./AdminSettingsRateLimitingTabPage', () => ({
  __esModule: true,
  default: () => <div data-testid="rate-limiting-tab-page">Rate Limiting Content</div>
}));

jest.mock('./AdminSettingsInfrastructureTabPage', () => ({
  AdminSettingsInfrastructureTabPage: () => <div data-testid="infrastructure-tab-page">Infrastructure Content</div>
}));

jest.mock('./AdminSettingsProxyTabPage', () => ({
  AdminSettingsProxyTabPage: () => <div data-testid="proxy-tab-page">Proxy Content</div>
}));

describe('AdminSettingsPage', () => {
  const createMockStore = (user: { id: string; email: string; permissions: string[] } | null) => {
    return configureStore({
      reducer: {
        auth: (state = { user, isAuthenticated: !!user }) => state
      }
    });
  };

  const mockUserWithPermissions = {
    id: 'test-user-id',
    email: 'admin@test.com',
    permissions: ['admin.settings.read', 'admin.settings.update']
  };

  const mockUserWithoutPermissions = {
    id: 'test-user-id',
    email: 'user@test.com',
    permissions: [] as string[]
  };

  beforeEach(() => {
    // Reset mock and set default behavior
    mockHasPermissions.mockReset();
    mockHasPermissions.mockImplementation((user, permissions) => {
      if (!user) return false;
      return permissions.every((p: string) => user.permissions?.includes(p));
    });
  });

  const renderComponent = (user = mockUserWithPermissions, initialRoute = '/app/admin/settings') => {
    const store = createMockStore(user);
    return render(
      <Provider store={store}>
        <BreadcrumbProvider>
          <MemoryRouter initialEntries={[initialRoute]}>
            <Routes>
              <Route path="/app/admin/settings/*" element={<AdminSettingsPage />} />
              <Route path="/app" element={<div data-testid="redirected">Redirected to App</div>} />
            </Routes>
          </MemoryRouter>
        </BreadcrumbProvider>
      </Provider>
    );
  };

  describe('Component Rendering', () => {
    it('renders the page with correct title', () => {
      renderComponent();
      expect(screen.getByText('Admin Settings')).toBeInTheDocument();
    });

    it('renders the page with correct description', () => {
      renderComponent();
      expect(screen.getByText('System administration and configuration')).toBeInTheDocument();
    });

    it('renders the admin settings tabs', () => {
      renderComponent();
      expect(screen.getByTestId('admin-settings-tabs')).toBeInTheDocument();
    });

    it('renders the overview tab content by default', () => {
      renderComponent();
      expect(screen.getByTestId('overview-tab-page')).toBeInTheDocument();
    });
  });

  describe('Breadcrumbs', () => {
    it('displays Dashboard in breadcrumbs', () => {
      renderComponent();
      expect(screen.getByRole('link', { name: /Dashboard/i })).toBeInTheDocument();
    });

    it('displays Settings in breadcrumbs', () => {
      renderComponent();
      expect(screen.getByText('Settings')).toBeInTheDocument();
    });
  });

  describe('Permission Handling', () => {
    it('redirects when user lacks admin.settings.read permission', () => {
      renderComponent(mockUserWithoutPermissions);
      expect(screen.getByTestId('redirected')).toBeInTheDocument();
    });

    it('renders page when user has required permission', () => {
      renderComponent(mockUserWithPermissions);
      expect(screen.getByText('Admin Settings')).toBeInTheDocument();
      expect(screen.getByTestId('admin-settings-tabs')).toBeInTheDocument();
    });
  });

  describe('Page Structure', () => {
    it('renders page with all main sections', () => {
      renderComponent();
      expect(screen.getByText('Admin Settings')).toBeInTheDocument();
      expect(screen.getByTestId('admin-settings-tabs')).toBeInTheDocument();
    });
  });

  // fc-45: one tab list (CORE_ADMIN_SETTINGS_TABS) drives the tab bar, the
  // breadcrumb and the routes, so they cannot drift apart again.
  describe('Single tab list', () => {
    it.each(CORE_ADMIN_SETTINGS_TABS.map((tab) => [tab.id, tab] as const))(
      'routes the %s tab and names it in the breadcrumb',
      (_id, tab) => {
        renderComponent(mockUserWithPermissions, tab.href);
        expect(screen.getByTestId(`${tab.id}-tab-page`)).toBeInTheDocument();
        const trail = screen.getByRole('navigation', { name: 'Breadcrumb' });
        if (tab.id !== 'overview') expect(trail).toHaveTextContent(tab.label);
      }
    );

    it('includes the Autonomy tab', () => {
      renderComponent(mockUserWithPermissions, '/app/admin/settings/autonomy');
      expect(screen.getByRole('navigation', { name: 'Breadcrumb' })).toHaveTextContent('Autonomy');
    });

    it('has no Development tab', () => {
      expect(CORE_ADMIN_SETTINGS_TABS.map((tab) => tab.id)).not.toContain('development');
    });

    it.each(['/app/admin/settings/development', '/app/admin/settings/no-such-tab'])(
      'does not redirect an unknown settings path (%s) to the overview',
      (path) => {
        renderComponent(mockUserWithPermissions, path);
        expect(screen.queryByTestId('overview-tab-page')).not.toBeInTheDocument();
        expect(screen.getByText('This settings tab does not exist.')).toBeInTheDocument();
      }
    );
  });
});
