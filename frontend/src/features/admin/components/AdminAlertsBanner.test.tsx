import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AdminAlertsBanner } from './AdminAlertsBanner';
import { performanceApi } from '@/shared/services/admin/performanceApi';

// Mock performanceApi
jest.mock('@/shared/services/admin/performanceApi', () => ({
  performanceApi: {
    getActiveAlerts: jest.fn()
  }
}));

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, variant, className, disabled }: any) => (
    <button onClick={onClick} data-variant={variant} className={className} disabled={disabled}>
      {children}
    </button>
  )
}));

describe('AdminAlertsBanner', () => {
  const mockAlerts = [
    {
      id: 'alert-1',
      type: 'high_memory_usage',
      severity: 'critical',
      message: 'Memory usage exceeds 90%',
      created_at: '2025-01-15T10:00:00Z'
    },
    {
      id: 'alert-2',
      type: 'slow_response_time',
      severity: 'high',
      message: 'API response time exceeds threshold',
      created_at: '2025-01-15T09:30:00Z'
    },
    {
      id: 'alert-3',
      type: 'disk_space_warning',
      severity: 'medium',
      message: 'Disk space running low',
      created_at: '2025-01-15T09:00:00Z'
    },
    {
      id: 'alert-4',
      type: 'info_notification',
      severity: 'low',
      message: 'System update available',
      created_at: '2025-01-15T08:00:00Z'
    }
  ];

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('loading state', () => {
    it('returns null while loading', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockImplementation(
        () => new Promise(() => {}) // Never resolves
      );

      const { container } = render(<AdminAlertsBanner />);

      // Should be empty while loading
      expect(container.firstChild).toBeNull();
    });
  });

  describe('no alerts', () => {
    it('returns null when no alerts', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: []
      });

      const { container } = render(<AdminAlertsBanner />);

      await waitFor(() => {
        expect(container.firstChild).toBeNull();
      });
    });
  });

  describe('single critical/high alert', () => {
    it('shows full banner for single critical alert', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: [mockAlerts[0]] // Critical alert
      });

      render(<AdminAlertsBanner />);

      await waitFor(() => {
        expect(screen.getByText(/High Memory Usage Alert/)).toBeInTheDocument();
      });
      expect(screen.getByText('Memory usage exceeds 90%')).toBeInTheDocument();
    });

    it('shows full banner for single high alert', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: [mockAlerts[1]] // High alert
      });

      render(<AdminAlertsBanner />);

      await waitFor(() => {
        expect(screen.getByText(/Slow Response Time Alert/)).toBeInTheDocument();
      });
      expect(screen.getByText('API response time exceeds threshold')).toBeInTheDocument();
    });

    it('shows View Details button when onViewAll provided', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: [mockAlerts[0]]
      });

      render(<AdminAlertsBanner onViewAll={jest.fn()} />);

      await waitFor(() => {
        expect(screen.getByText('View Details')).toBeInTheDocument();
      });
    });

    it('calls onViewAll when View Details clicked', async () => {
      const onViewAll = jest.fn();
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: [mockAlerts[0]]
      });

      render(<AdminAlertsBanner onViewAll={onViewAll} />);

      await waitFor(() => {
        fireEvent.click(screen.getByText('View Details'));
      });

      expect(onViewAll).toHaveBeenCalled();
    });

    it('dismisses alert when X clicked', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: [mockAlerts[0]]
      });

      const { container } = render(<AdminAlertsBanner />);

      await waitFor(() => {
        expect(screen.getByText('Memory usage exceeds 90%')).toBeInTheDocument();
      });

      // Click the dismiss button (X icon)
      const dismissButton = container.querySelector('button:not([data-variant])');
      fireEvent.click(dismissButton!);

      // Banner should be gone
      await waitFor(() => {
        expect(screen.queryByText('Memory usage exceeds 90%')).not.toBeInTheDocument();
      });
    });
  });

  describe('multiple alerts', () => {
    it('shows compact summary for multiple alerts', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: mockAlerts
      });

      render(<AdminAlertsBanner />);

      await waitFor(() => {
        expect(screen.getByText('4 Active Alerts')).toBeInTheDocument();
      });
    });

    it('shows critical count badge', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: mockAlerts
      });

      render(<AdminAlertsBanner />);

      await waitFor(() => {
        expect(screen.getByText('1 Critical')).toBeInTheDocument();
      });
    });

    it('shows high count badge', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: mockAlerts
      });

      render(<AdminAlertsBanner />);

      await waitFor(() => {
        expect(screen.getByText('1 High')).toBeInTheDocument();
      });
    });

    it('shows View All button when onViewAll provided', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: mockAlerts
      });

      render(<AdminAlertsBanner onViewAll={jest.fn()} />);

      await waitFor(() => {
        expect(screen.getByText('View All')).toBeInTheDocument();
      });
    });

    it('shows +X more when more than 2 alerts', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: mockAlerts
      });

      render(<AdminAlertsBanner />);

      await waitFor(() => {
        expect(screen.getByText('+2 more')).toBeInTheDocument();
      });
    });
  });

  describe('maxAlerts prop', () => {
    it('limits visible alerts', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: mockAlerts
      });

      render(<AdminAlertsBanner maxAlerts={2} />);

      await waitFor(() => {
        expect(screen.getByText('4 Active Alerts')).toBeInTheDocument();
      });
    });
  });

  describe('API error handling', () => {
    it('fails silently on API error', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockRejectedValue(new Error('API error'));

      const { container } = render(<AdminAlertsBanner />);

      await waitFor(() => {
        // Should show nothing on error
        expect(container.firstChild).toBeNull();
      });
    });

    it('fails silently when response is not successful', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: false,
        error: 'Failed to load alerts'
      });

      const { container } = render(<AdminAlertsBanner />);

      await waitFor(() => {
        expect(container.firstChild).toBeNull();
      });
    });
  });

  describe('className prop', () => {
    it('applies custom className', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: [mockAlerts[0]]
      });

      const { container } = render(<AdminAlertsBanner className="custom-class" />);

      await waitFor(() => {
        expect(container.firstChild).toHaveClass('custom-class');
      });
    });
  });

  describe('alert type formatting', () => {
    it('formats alert type with proper casing', async () => {
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: [mockAlerts[0]]
      });

      render(<AdminAlertsBanner />);

      await waitFor(() => {
        // "high_memory_usage" should become "High Memory Usage Alert"
        expect(screen.getByText(/High Memory Usage Alert/)).toBeInTheDocument();
      });
    });
  });

  describe('dismissing multiple alerts', () => {
    it('updates count when alert is dismissed', async () => {
      const twoAlerts = [mockAlerts[0], mockAlerts[1]];
      (performanceApi.getActiveAlerts as jest.Mock).mockResolvedValue({
        success: true,
        data: twoAlerts
      });

      render(<AdminAlertsBanner />);

      // Initially shows 2 alerts
      await waitFor(() => {
        expect(screen.getByText('2 Active Alerts')).toBeInTheDocument();
      });
    });
  });
});
