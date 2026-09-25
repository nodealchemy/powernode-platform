import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { AdminMaintenancePage } from './AdminMaintenancePage';
import { maintenanceApi } from '@/shared/services/admin/maintenanceApi';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';

// Mock the maintenance API
jest.mock('@/shared/services/admin/maintenanceApi', () => ({
  maintenanceApi: {
    getMaintenanceStatus: jest.fn(),
    getBackups: jest.fn(),
    getCleanupStats: jest.fn(),
    getMaintenanceSchedules: jest.fn(),
    setMaintenanceMode: jest.fn(),
    createBackup: jest.fn(),
    deleteBackup: jest.fn(),
    restoreBackup: jest.fn(),
    downloadBackup: jest.fn(),
    runCleanup: jest.fn(),
    createMaintenanceSchedule: jest.fn(),
    updateMaintenanceSchedule: jest.fn(),
    deleteMaintenanceSchedule: jest.fn(),
    runScheduledTask: jest.fn(),
    formatBytes: jest.fn((bytes: number) => `${bytes} B`),
    getStatusColor: jest.fn(() => 'text-theme-success-fg'),
    getStatusBgColor: jest.fn(() => 'bg-theme-success-bg'),
    clearCache: jest.fn(),
    rebuildIndexes: jest.fn(),
    vacuumDatabase: jest.fn(),
    restartServices: jest.fn(),
    flushCache: jest.fn(),
    optimizeDatabase: jest.fn()
  }
}));

// Mock hooks
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn()
  })
}));

describe('AdminMaintenancePage', () => {
  let store: ReturnType<typeof configureStore>;

  const mockMaintenanceStatus = {
    mode: false,
    message: ''
  };

  const mockBackups = [
    { id: 'backup-1', filename: 'backup-1.sql', size: 1024000, status: 'completed' as const, created_at: '2024-01-15T10:00:00Z', type: 'manual' as const },
    { id: 'backup-2', filename: 'backup-2.sql', size: 2048000, status: 'completed' as const, created_at: '2024-01-14T10:00:00Z', type: 'scheduled' as const }
  ];

  const mockCleanupStats = {
    old_logs: 100,
    expired_sessions: 50,
    temporary_files: 25,
    audit_logs_older_than_90_days: 200,
    orphaned_uploads: 10,
    cache_entries: 500
  };

  const mockSchedules = [
    { id: 'schedule-1', type: 'backup' as const, scheduled_at: '2024-01-16T02:00:00Z', frequency: 'daily' as const, enabled: true, description: 'Daily backup', next_run: '2024-01-16T02:00:00Z' },
    { id: 'schedule-2', type: 'cleanup' as const, scheduled_at: '2024-01-16T03:00:00Z', frequency: 'weekly' as const, enabled: false, description: 'Weekly cleanup', next_run: '2024-01-20T03:00:00Z' }
  ];

  beforeEach(() => {
    jest.clearAllMocks();

    store = configureStore({
      reducer: {
        auth: (state = { user: null, isAuthenticated: false }) => state
      }
    });

    (maintenanceApi.getMaintenanceStatus as jest.Mock).mockResolvedValue(mockMaintenanceStatus);
    (maintenanceApi.getBackups as jest.Mock).mockResolvedValue(mockBackups);
    (maintenanceApi.getCleanupStats as jest.Mock).mockResolvedValue(mockCleanupStats);
    (maintenanceApi.getMaintenanceSchedules as jest.Mock).mockResolvedValue(mockSchedules);
  });

  const renderComponent = async (initialRoute = '/app/admin/maintenance') => {
    let result: ReturnType<typeof render>;
    await act(async () => {
      result = render(
        <Provider store={store}>
          <BreadcrumbProvider>
            <MemoryRouter initialEntries={[initialRoute]}>
              <AdminMaintenancePage />
            </MemoryRouter>
          </BreadcrumbProvider>
        </Provider>
      );
    });
    return result!;
  };

  describe('Component Rendering', () => {
    it('renders the page with correct title', async () => {
      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('System Maintenance')).toBeInTheDocument();
      });
    });

    it('fetches all maintenance data on mount', async () => {
      await renderComponent();

      await waitFor(() => {
        expect(maintenanceApi.getMaintenanceStatus).toHaveBeenCalled();
        expect(maintenanceApi.getBackups).toHaveBeenCalled();
        expect(maintenanceApi.getCleanupStats).toHaveBeenCalled();
        expect(maintenanceApi.getMaintenanceSchedules).toHaveBeenCalled();
      });
    });
  });

  describe('Tab Navigation', () => {
    it('displays maintenance tabs', async () => {
      await renderComponent();

      await waitFor(() => {
        // Check tabs are present - use getAllByRole to find buttons
        const buttons = screen.getAllByRole('button');
        const tabNames = buttons.map(b => b.textContent);
        expect(tabNames.some(name => name?.includes('Overview'))).toBe(true);
        expect(tabNames.some(name => name?.includes('Maintenance Mode'))).toBe(true);
        expect(tabNames.some(name => name?.includes('Scheduled Tasks'))).toBe(true);
      });
    });

    // fc-47: platform health is on /app/status. Maintenance keeps no System
    // Health tab and renders no health verdict of its own.
    it('has no System Health tab', async () => {
      await renderComponent();

      await screen.findByRole('link', { name: /Platform status/ });
      const tabNames = screen.getAllByRole('button').map(b => b.textContent);
      expect(tabNames.some(name => name?.includes('System Health'))).toBe(false);
    });

    it('falls back to Overview on a path that is not a tab', async () => {
      await renderComponent('/app/admin/maintenance/not-a-tab');

      expect(await screen.findByRole('link', { name: /Platform status/ })).toBeInTheDocument();
    });

    it('links to /app/status for platform health', async () => {
      await renderComponent();

      const card = await screen.findByRole('link', { name: /Platform status/ });
      expect(card).toHaveAttribute('href', '/app/status');
    });

    it('defaults to Overview tab', async () => {
      await renderComponent();

      expect(await screen.findByRole('link', { name: /Platform status/ })).toBeInTheDocument();
    });
  });

  describe('Overview Tab', () => {
    it('says when maintenance mode is off', async () => {
      await renderComponent();

      expect(await screen.findByText('Maintenance mode is off')).toBeInTheDocument();
    });

    it('shows maintenance mode warning when active', async () => {
      (maintenanceApi.getMaintenanceStatus as jest.Mock).mockResolvedValue({
        mode: true,
        message: 'Under maintenance'
      });

      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText(/maintenance mode is currently active/i)).toBeInTheDocument();
      });
    });
  });

  // fc-47 review H1: the overview used to render a health verdict, a service
  // grid and host metrics from GET /admin/maintenance/health, whose shape
  // ({overall_status, checks}) it never matched. /app/status shows them.
  describe('No health of its own', () => {
    it('renders no health verdict, service grid or system metrics', async () => {
      await renderComponent();
      await screen.findByRole('link', { name: /Platform status/ });

      [
        'All Systems Operational', 'Some Services Degraded', 'Critical Issues Detected',
        'Service Health Overview', 'System Metrics', 'Service Management'
      ].forEach((text) => expect(screen.queryByText(text)).not.toBeInTheDocument());
    });
  });

  describe('Error Handling', () => {
    it('displays error message when API fails', async () => {
      (maintenanceApi.getMaintenanceStatus as jest.Mock).mockRejectedValue(new Error('Network error'));
      (maintenanceApi.getBackups as jest.Mock).mockRejectedValue(new Error('Network error'));
      (maintenanceApi.getCleanupStats as jest.Mock).mockRejectedValue(new Error('Network error'));
      (maintenanceApi.getMaintenanceSchedules as jest.Mock).mockRejectedValue(new Error('Network error'));

      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Error Loading Maintenance Data')).toBeInTheDocument();
      });
    });

    it('shows retry button on error', async () => {
      (maintenanceApi.getMaintenanceStatus as jest.Mock).mockRejectedValue(new Error('Network error'));
      (maintenanceApi.getBackups as jest.Mock).mockRejectedValue(new Error('Network error'));
      (maintenanceApi.getCleanupStats as jest.Mock).mockRejectedValue(new Error('Network error'));
      (maintenanceApi.getMaintenanceSchedules as jest.Mock).mockRejectedValue(new Error('Network error'));

      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Try Again')).toBeInTheDocument();
      });
    });
  });

  describe('Page Actions', () => {
    it('shows refresh button', async () => {
      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Refresh')).toBeInTheDocument();
      });
    });

    it('refreshes data when refresh button clicked', async () => {
      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Refresh')).toBeInTheDocument();
      });

      const initialCallCount = (maintenanceApi.getMaintenanceStatus as jest.Mock).mock.calls.length;

      await act(async () => {
        fireEvent.click(screen.getByText('Refresh'));
      });

      await waitFor(() => {
        expect((maintenanceApi.getMaintenanceStatus as jest.Mock).mock.calls.length).toBeGreaterThan(initialCallCount);
      });
    });
  });

  describe('Breadcrumbs', () => {
    it('displays Dashboard in breadcrumbs', async () => {
      await renderComponent();

      await waitFor(() => {
        expect(screen.getByRole('link', { name: /Dashboard/i })).toBeInTheDocument();
      });
    });

    it('displays Maintenance in breadcrumbs', async () => {
      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Maintenance')).toBeInTheDocument();
      });
    });
  });
});
