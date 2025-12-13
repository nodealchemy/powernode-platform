import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AdminDashboard } from './AdminDashboard';

// Mock notifications hook
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification
  })
}));

// Mock admin settings API
const mockGetOverview = jest.fn();
jest.mock('../services/adminSettingsApi', () => ({
  adminSettingsApi: {
    getOverview: (...args: any[]) => mockGetOverview(...args)
  }
}));

// Mock child components
jest.mock('./AdminMetricsGrid', () => ({
  AdminMetricsGrid: ({ metrics, loading }: any) => (
    <div data-testid="metrics-grid" data-loading={loading}>
      <span>Total Users: {metrics.total_users}</span>
      <span>Total Accounts: {metrics.total_accounts}</span>
    </div>
  )
}));

jest.mock('./AdminSystemHealth', () => ({
  AdminSystemHealth: ({ systemHealth, uptime, loading }: any) => (
    <div data-testid="system-health" data-loading={loading}>
      <span>Health: {systemHealth}</span>
      <span>Uptime: {uptime}%</span>
    </div>
  )
}));

jest.mock('./AdminAlertsBanner', () => ({
  AdminAlertsBanner: ({ onViewAll }: any) => (
    <div data-testid="alerts-banner">
      <button onClick={onViewAll}>View Alerts</button>
    </div>
  )
}));

jest.mock('./SystemAlertsPanel', () => ({
  SystemAlertsPanel: () => <div data-testid="alerts-panel">Alerts Panel</div>
}));

jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, variant }: any) => (
    <button onClick={onClick} disabled={disabled} data-variant={variant}>
      {children}
    </button>
  )
}));

describe('AdminDashboard', () => {
  const mockOverviewData = {
    metrics: {
      total_users: 150,
      total_accounts: 50,
      active_accounts: 45,
      suspended_accounts: 3,
      cancelled_accounts: 2,
      total_subscriptions: 48,
      active_subscriptions: 45,
      trial_subscriptions: 5,
      total_revenue: 125000,
      monthly_revenue: 12500,
      failed_payments: 2,
      webhook_events_today: 320,
      system_health: 'healthy',
      uptime: 99.9
    },
    payment_gateways: {
      stripe: {
        connected: true,
        environment: 'production',
        webhook_status: 'active',
        last_webhook: '2025-01-15T10:00:00Z'
      },
      paypal: {
        connected: true,
        environment: 'production',
        webhook_status: 'active',
        last_webhook: '2025-01-15T09:30:00Z'
      }
    },
    recent_users: [
      {
        id: 'user-1',
        email: 'john@example.com',
        full_name: 'John Doe',
        created_at: '2025-01-15T10:00:00Z',
        account: { name: 'Acme Corp' }
      },
      {
        id: 'user-2',
        email: 'jane@example.com',
        full_name: 'Jane Smith',
        created_at: '2025-01-14T10:00:00Z',
        account: { name: 'Beta Inc' }
      }
    ],
    recent_accounts: [
      {
        id: 'acc-1',
        name: 'Acme Corp',
        status: 'active',
        users_count: 5,
        subscription: { plan: { name: 'Professional' } },
        created_at: '2025-01-15T08:00:00Z'
      },
      {
        id: 'acc-2',
        name: 'Beta Inc',
        status: 'suspended',
        users_count: 3,
        subscription: { plan: { name: 'Basic' } },
        created_at: '2025-01-14T08:00:00Z'
      }
    ],
    recent_logs: [
      {
        id: 'log-1',
        message: 'User login successful',
        source: 'auth',
        level: 'info',
        timestamp: '2025-01-15T10:30:00Z'
      },
      {
        id: 'log-2',
        message: 'Payment failed',
        source: 'billing',
        level: 'error',
        timestamp: '2025-01-15T10:25:00Z'
      },
      {
        id: 'log-3',
        message: 'High memory usage',
        source: 'system',
        level: 'warning',
        timestamp: '2025-01-15T10:20:00Z'
      }
    ]
  };

  const defaultProps = {
    onNavigateToAlerts: jest.fn(),
    onNavigateToUsers: jest.fn(),
    onNavigateToAccounts: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetOverview.mockResolvedValue({
      success: true,
      data: mockOverviewData
    });
  });

  describe('loading state', () => {
    it('shows loading skeleton while fetching data', () => {
      mockGetOverview.mockImplementation(() => new Promise(() => {}));

      render(<AdminDashboard {...defaultProps} />);

      expect(document.querySelector('.animate-pulse')).toBeInTheDocument();
    });
  });

  describe('main content', () => {
    it('shows dashboard title and description', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Admin Dashboard')).toBeInTheDocument();
      });
      expect(screen.getByText('System overview and key metrics')).toBeInTheDocument();
    });

    it('shows refresh button', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Refresh')).toBeInTheDocument();
      });
    });

    it('renders metrics grid with data', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('metrics-grid')).toBeInTheDocument();
      });
      expect(screen.getByText('Total Users: 150')).toBeInTheDocument();
      expect(screen.getByText('Total Accounts: 50')).toBeInTheDocument();
    });

    it('renders system health component', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('system-health')).toBeInTheDocument();
      });
      expect(screen.getByText('Health: healthy')).toBeInTheDocument();
      expect(screen.getByText('Uptime: 99.9%')).toBeInTheDocument();
    });

    it('renders alerts banner', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('alerts-banner')).toBeInTheDocument();
      });
    });

    it('renders alerts panel', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('alerts-panel')).toBeInTheDocument();
      });
    });
  });

  describe('recent users section', () => {
    it('shows recent users header', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Recent Users')).toBeInTheDocument();
      });
    });

    it('displays user names', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('John Doe')).toBeInTheDocument();
      });
      expect(screen.getByText('Jane Smith')).toBeInTheDocument();
    });

    it('displays user emails', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('john@example.com')).toBeInTheDocument();
      });
      expect(screen.getByText('jane@example.com')).toBeInTheDocument();
    });

    it('displays user account names', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        // Acme Corp appears in both users section and accounts section
        const acmeCorpElements = screen.getAllByText('Acme Corp');
        expect(acmeCorpElements.length).toBeGreaterThan(0);
      });
    });

    it('shows View All button for users', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        const viewAllButtons = screen.getAllByText('View All');
        expect(viewAllButtons.length).toBeGreaterThan(0);
      });
    });

    it('calls onNavigateToUsers when View All clicked', async () => {
      const onNavigateToUsers = jest.fn();
      render(<AdminDashboard {...defaultProps} onNavigateToUsers={onNavigateToUsers} />);

      await waitFor(() => {
        expect(screen.getByText('Recent Users')).toBeInTheDocument();
      });

      const viewAllButtons = screen.getAllByText('View All');
      fireEvent.click(viewAllButtons[0]);

      expect(onNavigateToUsers).toHaveBeenCalled();
    });
  });

  describe('recent accounts section', () => {
    it('shows recent accounts header', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Recent Accounts')).toBeInTheDocument();
      });
    });

    it('displays account names', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        // Acme Corp appears in both users section (as account) and accounts section
        const acmeCorpElements = screen.getAllByText('Acme Corp');
        expect(acmeCorpElements.length).toBeGreaterThan(0);
      });
      // Beta Inc also appears in both users and accounts sections
      const betaIncElements = screen.getAllByText('Beta Inc');
      expect(betaIncElements.length).toBeGreaterThan(0);
    });

    it('displays account status badges', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('active')).toBeInTheDocument();
      });
      expect(screen.getByText('suspended')).toBeInTheDocument();
    });

    it('calls onNavigateToAccounts when View All clicked', async () => {
      const onNavigateToAccounts = jest.fn();
      render(<AdminDashboard {...defaultProps} onNavigateToAccounts={onNavigateToAccounts} />);

      await waitFor(() => {
        expect(screen.getByText('Recent Accounts')).toBeInTheDocument();
      });

      const viewAllButtons = screen.getAllByText('View All');
      // Second View All is for accounts
      fireEvent.click(viewAllButtons[1]);

      expect(onNavigateToAccounts).toHaveBeenCalled();
    });
  });

  describe('recent activity section', () => {
    it('shows recent activity header', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Recent Activity')).toBeInTheDocument();
      });
    });

    it('displays log messages', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('User login successful')).toBeInTheDocument();
      });
      expect(screen.getByText('Payment failed')).toBeInTheDocument();
      expect(screen.getByText('High memory usage')).toBeInTheDocument();
    });

    it('displays log levels', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('info')).toBeInTheDocument();
      });
      expect(screen.getByText('error')).toBeInTheDocument();
      expect(screen.getByText('warning')).toBeInTheDocument();
    });
  });

  describe('refresh functionality', () => {
    it('calls loadData when refresh button clicked', async () => {
      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Refresh')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Refresh'));

      await waitFor(() => {
        expect(mockGetOverview).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('error handling', () => {
    it('shows notification on API error', async () => {
      mockGetOverview.mockResolvedValue({
        success: false,
        error: 'Failed to load data'
      });

      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to load data', 'error');
      });
    });

    it('shows notification on API exception', async () => {
      mockGetOverview.mockRejectedValue(new Error('Network error'));

      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to load dashboard data', 'error');
      });
    });
  });

  describe('navigation callbacks', () => {
    it('calls onNavigateToAlerts from banner', async () => {
      const onNavigateToAlerts = jest.fn();
      render(<AdminDashboard {...defaultProps} onNavigateToAlerts={onNavigateToAlerts} />);

      await waitFor(() => {
        expect(screen.getByText('View Alerts')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('View Alerts'));

      expect(onNavigateToAlerts).toHaveBeenCalled();
    });
  });

  describe('empty states', () => {
    it('shows empty message when no recent users', async () => {
      mockGetOverview.mockResolvedValue({
        success: true,
        data: { ...mockOverviewData, recent_users: null }
      });

      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('No recent users')).toBeInTheDocument();
      });
    });

    it('shows empty message when no recent accounts', async () => {
      mockGetOverview.mockResolvedValue({
        success: true,
        data: { ...mockOverviewData, recent_accounts: null }
      });

      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('No recent accounts')).toBeInTheDocument();
      });
    });

    it('shows empty message when no recent activity', async () => {
      mockGetOverview.mockResolvedValue({
        success: true,
        data: { ...mockOverviewData, recent_logs: null }
      });

      render(<AdminDashboard {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('No recent activity')).toBeInTheDocument();
      });
    });
  });

  describe('className prop', () => {
    it('applies custom className', async () => {
      const { container } = render(<AdminDashboard {...defaultProps} className="custom-class" />);

      await waitFor(() => {
        expect(screen.getByText('Admin Dashboard')).toBeInTheDocument();
      });

      const wrapper = container.firstChild;
      expect(wrapper).toHaveClass('custom-class');
    });
  });
});
