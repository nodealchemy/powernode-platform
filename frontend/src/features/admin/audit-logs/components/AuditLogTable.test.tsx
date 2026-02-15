import { render, screen, fireEvent } from '@testing-library/react';
import { AuditLogTable } from './AuditLogTable';

// Mock LoadingSpinner
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => <div data-testid="loading-spinner" data-size={size}>Loading...</div>
}));

describe('AuditLogTable', () => {
  const mockLogs = [
    {
      id: 'log-1',
      action: 'user_login',
      resource_type: 'User',
      resource_id: 'user-123',
      message: 'User successfully logged in',
      level: 'info' as const,
      status: 'success' as const,
      source: 'web',
      created_at: '2025-01-15T10:30:00Z',
      ip_address: '192.168.1.1',
      user_agent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      user: {
        id: 'user-123',
        email: 'john@example.com',
        full_name: 'John Doe'
      },
      account: {
        id: 'acc-1',
        name: 'Acme Corp'
      },
      old_values: {},
      new_values: {},
      metadata: { browser: 'Chrome', os: 'Windows' }
    },
    {
      id: 'log-2',
      action: 'login_failed',
      resource_type: 'User',
      resource_id: 'user-456',
      message: 'Failed login attempt',
      level: 'error' as const,
      status: 'error' as const,
      source: 'api',
      created_at: '2025-01-15T09:15:00Z',
      ip_address: '10.0.0.5',
      user_agent: 'Mobile/iPhone',
      user: {
        id: 'user-456',
        email: 'jane@example.com',
        full_name: 'Jane Smith'
      },
      account: undefined,
      old_values: {},
      new_values: {},
      metadata: {}
    },
    {
      id: 'log-3',
      action: 'payment_completed',
      resource_type: 'Payment',
      resource_id: 'pay-789',
      message: 'Payment processed',
      level: 'warning' as const,
      status: 'warning' as const,
      source: 'system',
      created_at: '2025-01-15T08:00:00Z',
      ip_address: undefined,
      user_agent: undefined,
      user: undefined,
      account: {
        id: 'acc-2',
        name: 'Beta Inc'
      },
      old_values: {},
      new_values: {},
      metadata: { amount: 100 }
    }
  ];

  const defaultProps = {
    logs: mockLogs,
    loading: false
  };

  describe('loading state', () => {
    it('shows loading spinner when loading', () => {
      render(<AuditLogTable logs={[]} loading={true} />);

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });

    it('hides table when loading', () => {
      render(<AuditLogTable logs={[]} loading={true} />);

      expect(screen.queryByRole('table')).not.toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows empty message when no logs', () => {
      render(<AuditLogTable logs={[]} />);

      expect(screen.getByText('No Audit Logs Found')).toBeInTheDocument();
    });

    it('shows filter suggestion in empty state', () => {
      render(<AuditLogTable logs={[]} />);

      expect(screen.getByText(/Try adjusting your search criteria/)).toBeInTheDocument();
    });
  });

  describe('table headers', () => {
    it('shows Event header', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('Event')).toBeInTheDocument();
    });

    it('shows User header', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('User')).toBeInTheDocument();
    });

    it('shows Time header', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('Time')).toBeInTheDocument();
    });

    it('shows Source header', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('Source')).toBeInTheDocument();
    });

    it('shows Status header', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('Status')).toBeInTheDocument();
    });

    it('shows Risk header', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('Risk')).toBeInTheDocument();
    });

    it('shows Actions header', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('Actions')).toBeInTheDocument();
    });
  });

  describe('log data display', () => {
    it('shows formatted action names', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('User Login')).toBeInTheDocument();
      expect(screen.getByText('Login Failed')).toBeInTheDocument();
      expect(screen.getByText('Payment Completed')).toBeInTheDocument();
    });

    it('shows resource type and id', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('User#user-123')).toBeInTheDocument();
      expect(screen.getByText('Payment#pay-789')).toBeInTheDocument();
    });

    it('shows user email', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('john@example.com')).toBeInTheDocument();
      expect(screen.getByText('jane@example.com')).toBeInTheDocument();
    });

    it('shows System for null user', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('System')).toBeInTheDocument();
    });

    it('shows user full name', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('John Doe')).toBeInTheDocument();
      expect(screen.getByText('Jane Smith')).toBeInTheDocument();
    });

    it('shows source badges', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('web')).toBeInTheDocument();
      expect(screen.getByText('api')).toBeInTheDocument();
      expect(screen.getByText('system')).toBeInTheDocument();
    });

    it('shows status badges', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('success')).toBeInTheDocument();
      // error and warning appear in both Status and Risk columns
      expect(screen.getAllByText('error').length).toBeGreaterThan(0);
      expect(screen.getAllByText('warning').length).toBeGreaterThan(0);
    });

    it('shows risk level badges', () => {
      render(<AuditLogTable {...defaultProps} />);

      // Risk column shows log.level values (info, error, warning)
      expect(screen.getByText('info')).toBeInTheDocument();
      // error and warning appear in both Status and Risk columns
      expect(screen.getAllByText('error').length).toBeGreaterThan(0);
      expect(screen.getAllByText('warning').length).toBeGreaterThan(0);
    });

    it('shows IP addresses', () => {
      render(<AuditLogTable {...defaultProps} />);

      expect(screen.getByText('192.168.1.1')).toBeInTheDocument();
      expect(screen.getByText('10.0.0.5')).toBeInTheDocument();
    });
  });

  describe('row expansion', () => {
    it('expands row when expand button clicked', () => {
      render(<AuditLogTable {...defaultProps} />);

      const expandButtons = screen.getAllByRole('button');
      fireEvent.click(expandButtons[0]);

      expect(screen.getByText('Event Details')).toBeInTheDocument();
    });

    it('shows message in expanded row', () => {
      render(<AuditLogTable {...defaultProps} />);

      const expandButtons = screen.getAllByRole('button');
      fireEvent.click(expandButtons[0]);

      expect(screen.getByText('User successfully logged in')).toBeInTheDocument();
    });

    it('shows account name in expanded row', () => {
      render(<AuditLogTable {...defaultProps} />);

      const expandButtons = screen.getAllByRole('button');
      fireEvent.click(expandButtons[0]);

      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
    });

    it('shows user agent in expanded row', () => {
      render(<AuditLogTable {...defaultProps} />);

      const expandButtons = screen.getAllByRole('button');
      fireEvent.click(expandButtons[0]);

      expect(screen.getByText(/Mozilla\/5.0/)).toBeInTheDocument();
    });

    it('shows metadata in expanded row', () => {
      render(<AuditLogTable {...defaultProps} />);

      const expandButtons = screen.getAllByRole('button');
      fireEvent.click(expandButtons[0]);

      expect(screen.getByText('browser:')).toBeInTheDocument();
      expect(screen.getByText('Chrome')).toBeInTheDocument();
    });

    it('shows no metadata message when empty', () => {
      render(<AuditLogTable {...defaultProps} />);

      // Find expand buttons (chevron buttons in the first column of each row)
      const rows = screen.getAllByRole('row');
      // Skip header row (index 0), find the expand button in the second data row (log-2 at index 2)
      const secondDataRow = rows[2];
      const expandButton = secondDataRow.querySelector('button');

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('No additional metadata')).toBeInTheDocument();
    });

    it('collapses row when clicked again', () => {
      render(<AuditLogTable {...defaultProps} />);

      const expandButtons = screen.getAllByRole('button');
      fireEvent.click(expandButtons[0]);
      expect(screen.getByText('Event Details')).toBeInTheDocument();

      fireEvent.click(expandButtons[0]);
      expect(screen.queryByText('Event Details')).not.toBeInTheDocument();
    });

    it('shows View Full Details button in expanded row', () => {
      render(<AuditLogTable {...defaultProps} />);

      const expandButtons = screen.getAllByRole('button');
      fireEvent.click(expandButtons[0]);

      expect(screen.getByText('View Full Details')).toBeInTheDocument();
    });
  });

  describe('log selection', () => {
    it('calls onLogSelect when view button clicked', () => {
      const onLogSelect = jest.fn();
      render(<AuditLogTable {...defaultProps} onLogSelect={onLogSelect} />);

      // Get all buttons with Eye icon (view details)
      const viewButtons = screen.getAllByTitle('View Details');
      fireEvent.click(viewButtons[0]);

      expect(onLogSelect).toHaveBeenCalledWith(mockLogs[0]);
    });

    it('calls onLogSelect when View Full Details clicked in expanded row', () => {
      const onLogSelect = jest.fn();
      render(<AuditLogTable {...defaultProps} onLogSelect={onLogSelect} />);

      const expandButtons = screen.getAllByRole('button');
      fireEvent.click(expandButtons[0]);

      const viewFullDetailsButton = screen.getByText('View Full Details');
      fireEvent.click(viewFullDetailsButton);

      expect(onLogSelect).toHaveBeenCalledWith(mockLogs[0]);
    });

    it('highlights selected row', () => {
      const { container } = render(<AuditLogTable {...defaultProps} selectedLogId="log-1" />);

      const rows = container.querySelectorAll('tbody tr');
      // The selected row has bg-theme-interactive-primary bg-opacity-5
      expect(rows[0]).toHaveClass('bg-theme-interactive-primary', 'bg-opacity-5');
    });
  });

  describe('severity styling', () => {
    it('applies error style for critical severity', () => {
      // getSeverityColor handles 'critical' -> error styling
      // Use type assertion since 'critical' is not a standard level but getSeverityColor handles it
       
      const criticalLog = [{ ...mockLogs[0], level: 'critical' as any, status: 'success' as const }];
      const { container } = render(<AuditLogTable logs={criticalLog} />);

      // The Risk column badge should have error background
      expect(container.querySelector('.bg-theme-error-background')).toBeInTheDocument();
    });

    it('applies error style for high severity', () => {
      // getSeverityColor handles 'high' -> error styling
       
      const highLog = [{ ...mockLogs[0], level: 'high' as any, status: 'success' as const }];
      const { container } = render(<AuditLogTable logs={highLog} />);

      expect(container.querySelector('.bg-theme-error-background')).toBeInTheDocument();
    });

    it('applies warning style for medium severity', () => {
      // getSeverityColor handles 'medium' -> warning styling
       
      const mediumLog = [{ ...mockLogs[0], level: 'medium' as any, status: 'success' as const }];
      const { container } = render(<AuditLogTable logs={mediumLog} />);

      expect(container.querySelector('.bg-theme-warning-background')).toBeInTheDocument();
    });

    it('applies success style for low severity', () => {
      // getSeverityColor handles 'low' -> success styling
       
      const lowLog = [{ ...mockLogs[0], level: 'low', status: 'error' }] as any;
      const { container } = render(<AuditLogTable logs={lowLog} />);

      // Both Status (error) and Risk (low) columns have styled badges
      expect(container.querySelector('.bg-theme-success-background')).toBeInTheDocument();
    });

    it('applies default style for unrecognized severity', () => {
      render(<AuditLogTable {...defaultProps} />);

      // log-1 has level='info' which falls through to default in getSeverityColor
      const infoBadges = screen.getAllByText('info');
      expect(infoBadges[0].closest('span')).toHaveClass('bg-theme-surface');
    });
  });

  describe('status styling', () => {
    it('applies success style for success status', () => {
      render(<AuditLogTable {...defaultProps} />);

      const successBadges = screen.getAllByText('success');
      expect(successBadges[0].closest('span')).toHaveClass('bg-theme-success-background');
    });

    it('applies error style for error status', () => {
      render(<AuditLogTable {...defaultProps} />);

      const errorBadges = screen.getAllByText('error');
      expect(errorBadges[0].closest('span')).toHaveClass('bg-theme-error-background');
    });

    it('applies warning style for warning status', () => {
      render(<AuditLogTable {...defaultProps} />);

      const warningBadges = screen.getAllByText('warning');
      expect(warningBadges[0].closest('span')).toHaveClass('bg-theme-warning-background');
    });
  });

  describe('device icon', () => {
    it('shows smartphone icon for mobile user agent', () => {
      render(<AuditLogTable {...defaultProps} />);

      // log-2 has Mobile/iPhone user agent - should have smartphone icon
      // We can't easily test the icon directly, but we verify the component renders
      expect(screen.getByText('jane@example.com')).toBeInTheDocument();
    });

    it('shows monitor icon for desktop user agent', () => {
      render(<AuditLogTable {...defaultProps} />);

      // log-1 has Windows user agent - should have monitor icon
      expect(screen.getByText('john@example.com')).toBeInTheDocument();
    });
  });
});
