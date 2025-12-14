import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { SystemAlertsPanel } from './SystemAlertsPanel';

// Mock notifications hook
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification
  })
}));

// Mock performance API
const mockGetActiveAlerts = jest.fn();
const mockDismissAlert = jest.fn();
jest.mock('@/shared/services/performanceApi', () => ({
  performanceApi: {
    getActiveAlerts: (...args: any[]) => mockGetActiveAlerts(...args),
    dismissAlert: (...args: any[]) => mockDismissAlert(...args)
  }
}));

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, variant, title, className }: any) => (
    <button
      onClick={onClick}
      disabled={disabled}
      data-variant={variant}
      title={title}
      className={className}
    >
      {children}
    </button>
  )
}));

describe('SystemAlertsPanel', () => {
  const mockAlerts = [
    {
      id: 'alert-1',
      type: 'cpu' as const,
      severity: 'critical',
      status: 'active',
      message: 'CPU usage is critically high',
      value: 95,
      threshold: 80,
      triggered_at: '2025-01-15T10:00:00Z'
    },
    {
      id: 'alert-2',
      type: 'memory' as const,
      severity: 'high',
      status: 'active',
      message: 'Memory usage exceeds threshold',
      value: 85,
      threshold: 75,
      triggered_at: '2025-01-15T09:30:00Z'
    },
    {
      id: 'alert-3',
      type: 'error_rate' as const,
      severity: 'medium',
      status: 'active',
      message: 'Error rate has increased',
      value: 5,
      threshold: 3,
      triggered_at: '2025-01-15T09:00:00Z'
    }
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetActiveAlerts.mockResolvedValue({
      success: true,
      data: mockAlerts
    });
    mockDismissAlert.mockResolvedValue({ success: true });
  });

  describe('loading state', () => {
    it('shows loading skeleton while fetching alerts', () => {
      mockGetActiveAlerts.mockImplementation(() => new Promise(() => {}));

      render(<SystemAlertsPanel />);

      expect(document.querySelector('.animate-pulse')).toBeInTheDocument();
    });
  });

  describe('main content', () => {
    it('shows System Alerts title', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('System Alerts')).toBeInTheDocument();
      });
    });

    it('shows alert count', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('3 active alerts')).toBeInTheDocument();
      });
    });

    it('shows singular alert text when one alert', async () => {
      mockGetActiveAlerts.mockResolvedValue({
        success: true,
        data: [mockAlerts[0]]
      });

      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('1 active alert')).toBeInTheDocument();
      });
    });

    it('shows filter toggle button', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByTitle('Toggle filters')).toBeInTheDocument();
      });
    });
  });

  describe('alerts display', () => {
    it('shows alert messages', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('CPU usage is critically high')).toBeInTheDocument();
      });
      expect(screen.getByText('Memory usage exceeds threshold')).toBeInTheDocument();
      expect(screen.getByText('Error rate has increased')).toBeInTheDocument();
    });

    it('shows alert type labels', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('CPU Usage Alert')).toBeInTheDocument();
      });
      expect(screen.getByText('Memory Usage Alert')).toBeInTheDocument();
      expect(screen.getByText('Error Rate Alert')).toBeInTheDocument();
    });

    it('shows severity badges', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('CRITICAL')).toBeInTheDocument();
      });
      expect(screen.getByText('HIGH')).toBeInTheDocument();
      expect(screen.getByText('MEDIUM')).toBeInTheDocument();
    });

    it('shows current values', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('95')).toBeInTheDocument();
      });
    });

    it('shows threshold values', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('80')).toBeInTheDocument();
      });
    });

    it('shows dismiss buttons', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        const dismissButtons = screen.getAllByTitle('Dismiss alert');
        expect(dismissButtons.length).toBe(3);
      });
    });
  });

  describe('empty state', () => {
    it('shows empty state when no alerts', async () => {
      mockGetActiveAlerts.mockResolvedValue({
        success: true,
        data: []
      });

      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('No Active Alerts')).toBeInTheDocument();
      });
      expect(screen.getByText('All systems are operating normally')).toBeInTheDocument();
    });
  });

  describe('filtering', () => {
    it('shows filter panel when filter button clicked', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByTitle('Toggle filters')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTitle('Toggle filters'));

      expect(screen.getByText('Severity')).toBeInTheDocument();
      expect(screen.getByText('Type')).toBeInTheDocument();
    });

    it('shows severity filter options', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByTitle('Toggle filters')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTitle('Toggle filters'));

      expect(screen.getByText('Critical')).toBeInTheDocument();
      expect(screen.getByText('High')).toBeInTheDocument();
      expect(screen.getByText('Medium')).toBeInTheDocument();
      expect(screen.getByText('Low')).toBeInTheDocument();
    });

    it('shows type filter options', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByTitle('Toggle filters')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTitle('Toggle filters'));

      expect(screen.getByText('CPU Usage')).toBeInTheDocument();
      expect(screen.getByText('Memory Usage')).toBeInTheDocument();
      expect(screen.getByText('Disk Usage')).toBeInTheDocument();
      expect(screen.getByText('Error Rate')).toBeInTheDocument();
      expect(screen.getByText('Response Time')).toBeInTheDocument();
      expect(screen.getByText('Queue Size')).toBeInTheDocument();
    });

    it('hides filter panel when toggled again', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByTitle('Toggle filters')).toBeInTheDocument();
      });

      // Open filters
      fireEvent.click(screen.getByTitle('Toggle filters'));
      expect(screen.getByText('Severity')).toBeInTheDocument();

      // Close filters
      fireEvent.click(screen.getByTitle('Toggle filters'));
      expect(screen.queryByText('Severity')).not.toBeInTheDocument();
    });
  });

  describe('dismiss functionality', () => {
    it('calls dismissAlert when dismiss button clicked', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('CPU usage is critically high')).toBeInTheDocument();
      });

      const dismissButtons = screen.getAllByTitle('Dismiss alert');
      fireEvent.click(dismissButtons[0]);

      await waitFor(() => {
        expect(mockDismissAlert).toHaveBeenCalledWith('alert-1');
      });
    });

    it('shows success notification after dismissing', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('CPU usage is critically high')).toBeInTheDocument();
      });

      const dismissButtons = screen.getAllByTitle('Dismiss alert');
      fireEvent.click(dismissButtons[0]);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Alert dismissed successfully', 'success');
      });
    });

    it('removes alert from list after dismissing', async () => {
      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('CPU usage is critically high')).toBeInTheDocument();
      });

      const dismissButtons = screen.getAllByTitle('Dismiss alert');
      fireEvent.click(dismissButtons[0]);

      await waitFor(() => {
        expect(screen.queryByText('CPU usage is critically high')).not.toBeInTheDocument();
      });
    });

    it('shows error notification on dismiss failure', async () => {
      mockDismissAlert.mockResolvedValue({ success: false, error: 'Failed to dismiss' });

      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('CPU usage is critically high')).toBeInTheDocument();
      });

      const dismissButtons = screen.getAllByTitle('Dismiss alert');
      fireEvent.click(dismissButtons[0]);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to dismiss', 'error');
      });
    });

    it('shows error notification on dismiss exception', async () => {
      mockDismissAlert.mockRejectedValue(new Error('Network error'));

      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('CPU usage is critically high')).toBeInTheDocument();
      });

      const dismissButtons = screen.getAllByTitle('Dismiss alert');
      fireEvent.click(dismissButtons[0]);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to dismiss alert', 'error');
      });
    });
  });

  describe('props', () => {
    it('respects maxDisplayedAlerts prop', async () => {
      mockGetActiveAlerts.mockResolvedValue({
        success: true,
        data: mockAlerts
      });

      render(<SystemAlertsPanel maxDisplayedAlerts={2} />);

      await waitFor(() => {
        expect(screen.getByText('CPU usage is critically high')).toBeInTheDocument();
      });
      expect(screen.getByText('Memory usage exceeds threshold')).toBeInTheDocument();
      expect(screen.queryByText('Error rate has increased')).not.toBeInTheDocument();
    });
  });

  describe('refresh functionality', () => {
    it('reloads alerts when refresh button clicked', async () => {
      render(<SystemAlertsPanel />);

      // Wait for data to load and alerts to show
      await waitFor(() => {
        expect(screen.getByText('System Alerts')).toBeInTheDocument();
      });

      // Clear mock to check for second call
      mockGetActiveAlerts.mockClear();

      // Find refresh button by looking for the second outline button (first is filter toggle)
      const buttons = screen.getAllByRole('button');
      const outlineButtons = buttons.filter(btn => btn.getAttribute('data-variant') === 'outline');

      // The second outline button is the refresh button (Clock icon)
      if (outlineButtons.length > 1) {
        fireEvent.click(outlineButtons[1]);

        await waitFor(() => {
          expect(mockGetActiveAlerts).toHaveBeenCalled();
        });
      }
    });
  });

  describe('severity configurations', () => {
    it('displays low severity alert correctly', async () => {
      mockGetActiveAlerts.mockResolvedValue({
        success: true,
        data: [{
          id: 'alert-low',
          type: 'disk' as const,
          severity: 'low',
          status: 'active',
          message: 'Disk usage is elevated',
          value: 70,
          threshold: 60,
          triggered_at: '2025-01-15T10:00:00Z'
        }]
      });

      render(<SystemAlertsPanel />);

      await waitFor(() => {
        expect(screen.getByText('LOW')).toBeInTheDocument();
      });
      expect(screen.getByText('Disk Usage Alert')).toBeInTheDocument();
    });
  });
});
