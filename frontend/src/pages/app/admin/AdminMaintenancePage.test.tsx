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
    getSystemHealth: jest.fn(),
    getSystemMetrics: jest.fn(),
    getBackups: jest.fn(),
    getCleanupStats: jest.fn(),
    getMaintenanceSchedules: jest.fn(),
    setMaintenanceMode: jest.fn(),
    scheduleMaintenanceMode: jest.fn(),
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
    formatUptime: jest.fn((seconds: number) => `${seconds}s`),
    getStatusColor: jest.fn(() => 'text-theme-success'),
    getStatusBgColor: jest.fn(() => 'bg-theme-success-background'),
    clearCache: jest.fn(),
    rebuildIndexes: jest.fn(),
    vacuumDatabase: jest.fn(),
    restartServices: jest.fn(),
    restartService: jest.fn(),
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

  const mockSystemHealth = {
    overall_status: 'healthy' as const,
    database: {
      status: 'healthy' as const,
      connection_time: 5,
      size: 1024000,
      last_backup: '2024-01-15T10:00:00Z'
    },
    redis: {
      status: 'healthy' as const,
      memory_usage: 50,
      connected_clients: 10
    },
    storage: {
      status: 'healthy' as const,
      total_space: 100000000,
      used_space: 50000000,
      available_space: 50000000
    },
    services: [
      { name: 'Sidekiq', status: 'healthy' as const, uptime: 86400, memory_usage: 256 }
    ]
  };

  const mockSystemMetrics = {
    cpu_usage: 45,
    memory_usage: 60,
    disk_usage: 70,
    active_users: 25,
    database_connections: 10,
    queue_size: 5,
    response_time_avg: 150,
    error_rate: 0.5,
    uptime: 86400
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
    (maintenanceApi.getSystemHealth as jest.Mock).mockResolvedValue(mockSystemHealth);
    (maintenanceApi.getSystemMetrics as jest.Mock).mockResolvedValue(mockSystemMetrics);
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
            <MemoryRouter initialEntries={[initialRoute]} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
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
        expect(maintenanceApi.getSystemHealth).toHaveBeenCalled();
        expect(maintenanceApi.getSystemMetrics).toHaveBeenCalled();
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

    it('defaults to Overview tab', async () => {
      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('All Systems Operational')).toBeInTheDocument();
      });
    });
  });

  describe('Overview Tab', () => {
    it('displays system status banner', async () => {
      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('All Systems Operational')).toBeInTheDocument();
      });
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

  describe('Health Status', () => {
    it('shows healthy status when all services are healthy', async () => {
      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('All Systems Operational')).toBeInTheDocument();
      });
    });

    it('shows degraded status when some services have issues', async () => {
      (maintenanceApi.getSystemHealth as jest.Mock).mockResolvedValue({
        ...mockSystemHealth,
        overall_status: 'warning'
      });

      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Some Services Degraded')).toBeInTheDocument();
      });
    });

    it('shows critical status when services are down', async () => {
      (maintenanceApi.getSystemHealth as jest.Mock).mockResolvedValue({
        ...mockSystemHealth,
        overall_status: 'critical'
      });

      await renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Critical Issues Detected')).toBeInTheDocument();
      });
    });
  });

  describe('Error Handling', () => {
    it('displays error message when API fails', async () => {
      (maintenanceApi.getMaintenanceStatus as jest.Mock).mockRejectedValue(new Error('Network error'));
      (maintenanceApi.getSystemHealth as jest.Mock).mockRejectedValue(new Error('Network error'));
      (maintenanceApi.getSystemMetrics as jest.Mock).mockRejectedValue(new Error('Network error'));
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
      (maintenanceApi.getSystemHealth as jest.Mock).mockRejectedValue(new Error('Network error'));
      (maintenanceApi.getSystemMetrics as jest.Mock).mockRejectedValue(new Error('Network error'));
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
