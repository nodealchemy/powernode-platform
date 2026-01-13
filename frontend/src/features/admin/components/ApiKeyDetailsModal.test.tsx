import { render, screen, fireEvent } from '@testing-library/react';
import { ApiKeyDetailsModal } from './ApiKeyDetailsModal';
import { DetailedApiKey } from '@/features/devops/api-keys/services/apiKeysApi';

// Mock apiKeysApi
jest.mock('@/features/devops/api-keys/services/apiKeysApi', () => ({
  apiKeysApi: {
    getStatusColor: (status: string) => {
      switch (status) {
        case 'active': return 'bg-theme-success text-theme-success';
        case 'revoked': return 'bg-theme-error text-theme-error';
        case 'expired': return 'bg-theme-warning text-theme-warning';
        default: return 'bg-theme-surface text-theme-secondary';
      }
    },
    getStatusText: (status: string) => {
      switch (status) {
        case 'active': return 'Active';
        case 'revoked': return 'Revoked';
        case 'expired': return 'Expired';
        default: return 'Unknown';
      }
    },
    formatScope: (scope: string) => scope.split(':').map((part: string) =>
      part.charAt(0).toUpperCase() + part.slice(1)
    ).join(' → '),
    getScopeCategoryColor: () => 'bg-theme-info text-theme-info',
    formatUsageCount: (count: number) => {
      if (count === 0) return '0';
      if (count < 1000) return count.toString();
      if (count < 1000000) return `${(count / 1000).toFixed(1)}K`;
      return `${(count / 1000000).toFixed(1)}M`;
    }
  }
}));

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, variant }: any) => (
    <button onClick={onClick} data-variant={variant}>
      {children}
    </button>
  )
}));

describe('ApiKeyDetailsModal', () => {
  const mockApiKey: DetailedApiKey = {
    id: 'key-1',
    name: 'Production API Key',
    description: 'Main production key',
    masked_key: 'pk_***abc123',
    status: 'active',
    scopes: ['read:account', 'write:billing', 'admin:users'],
    expires_at: '2025-12-31T23:59:59Z',
    last_used_at: '2025-01-15T10:30:00Z',
    usage_count: 15000,
    created_at: '2025-01-01T00:00:00Z',
    rate_limit_per_hour: 1000,
    rate_limit_per_day: 10000,
    allowed_ips: ['192.168.1.1', '10.0.0.0/8'],
    recent_usage: [
      {
        id: 'usage-1',
        endpoint: '/api/v1/accounts',
        method: 'GET',
        status_code: 200,
        request_count: 150,
        ip_address: '192.168.1.1',
        created_at: '2025-01-15T10:00:00Z'
      },
      {
        id: 'usage-2',
        endpoint: '/api/v1/billing',
        method: 'POST',
        status_code: 201,
        request_count: 45,
        ip_address: '192.168.1.1',
        created_at: '2025-01-15T09:30:00Z'
      },
      {
        id: 'usage-3',
        endpoint: '/api/v1/users',
        method: 'DELETE',
        status_code: 404,
        request_count: 5,
        ip_address: '10.0.0.5',
        created_at: '2025-01-15T09:00:00Z'
      }
    ],
    usage_stats: {
      requests_today: 500,
      requests_this_week: 3500,
      requests_this_month: 15000,
      average_requests_per_day: 483
    }
  };

  const defaultProps = {
    apiKey: mockApiKey,
    isOpen: true,
    onClose: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('closed state', () => {
    it('returns null when isOpen is false', () => {
      const { container } = render(
        <ApiKeyDetailsModal {...defaultProps} isOpen={false} />
      );

      expect(container.firstChild).toBeNull();
    });

    it('returns null when apiKey is null', () => {
      const { container } = render(
        <ApiKeyDetailsModal {...defaultProps} apiKey={null} />
      );

      expect(container.firstChild).toBeNull();
    });
  });

  describe('header', () => {
    it('shows API key name in header', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Production API Key')).toBeInTheDocument();
    });

    it('shows close button', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      const buttons = screen.getAllByRole('button');
      expect(buttons.length).toBeGreaterThan(0);
    });

    it('calls onClose when close button clicked', () => {
      const onClose = jest.fn();
      render(<ApiKeyDetailsModal {...defaultProps} onClose={onClose} />);

      const closeButton = screen.getByText('Close');
      fireEvent.click(closeButton);

      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('key information', () => {
    it('shows Key Information section', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Key Information')).toBeInTheDocument();
    });

    it('shows status label', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      // Status appears in key info and table header
      const statusElements = screen.getAllByText('Status');
      expect(statusElements.length).toBeGreaterThan(0);
    });

    it('shows Active status text', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Active')).toBeInTheDocument();
    });

    it('shows Revoked status for revoked key', () => {
      const revokedKey = { ...mockApiKey, status: 'revoked' as const };
      render(<ApiKeyDetailsModal {...defaultProps} apiKey={revokedKey} />);

      expect(screen.getByText('Revoked')).toBeInTheDocument();
    });

    it('shows Created label', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Created')).toBeInTheDocument();
    });

    it('shows Expires label when expires_at exists', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Expires')).toBeInTheDocument();
    });

    it('hides Expires when expires_at is null', () => {
      const noExpiryKey = { ...mockApiKey, expires_at: undefined };
      render(<ApiKeyDetailsModal {...defaultProps} apiKey={noExpiryKey} />);

      expect(screen.queryByText('Expires')).not.toBeInTheDocument();
    });

    it('shows Last Used label when last_used_at exists', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Last Used')).toBeInTheDocument();
    });

    it('shows Total Usage', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Total Usage')).toBeInTheDocument();
      // Usage is formatted and displayed with "requests" text
      expect(screen.getByText(/requests/)).toBeInTheDocument();
    });
  });

  describe('permissions section', () => {
    it('shows Permissions section', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Permissions')).toBeInTheDocument();
    });

    it('shows formatted scopes', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Read → Account')).toBeInTheDocument();
      expect(screen.getByText('Write → Billing')).toBeInTheDocument();
      expect(screen.getByText('Admin → Users')).toBeInTheDocument();
    });
  });

  describe('usage statistics', () => {
    it('shows Usage Statistics section', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Usage Statistics')).toBeInTheDocument();
    });

    it('shows Today requests', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Today')).toBeInTheDocument();
      expect(screen.getByText('500')).toBeInTheDocument();
    });

    it('shows This Week requests', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('This Week')).toBeInTheDocument();
      expect(screen.getByText('3500')).toBeInTheDocument();
    });

    it('shows This Month requests', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('This Month')).toBeInTheDocument();
      expect(screen.getByText('15000')).toBeInTheDocument();
    });

    it('shows Daily Average', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Daily Average')).toBeInTheDocument();
      expect(screen.getByText('483')).toBeInTheDocument();
    });
  });

  describe('rate limits', () => {
    it('shows Rate Limits section', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Rate Limits')).toBeInTheDocument();
    });

    it('shows Per Hour limit', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Per Hour')).toBeInTheDocument();
      expect(screen.getByText('1,000')).toBeInTheDocument();
    });

    it('shows Per Day limit', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Per Day')).toBeInTheDocument();
      expect(screen.getByText('10,000')).toBeInTheDocument();
    });

    it('hides Rate Limits when no limits set', () => {
      const noLimitsKey = {
        ...mockApiKey,
        rate_limit_per_hour: undefined,
        rate_limit_per_day: undefined
      };
      render(<ApiKeyDetailsModal {...defaultProps} apiKey={noLimitsKey} />);

      expect(screen.queryByText('Rate Limits')).not.toBeInTheDocument();
    });
  });

  describe('allowed IPs', () => {
    it('shows Allowed IPs section', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Allowed IPs')).toBeInTheDocument();
    });

    it('shows IP addresses', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('192.168.1.1')).toBeInTheDocument();
      expect(screen.getByText('10.0.0.0/8')).toBeInTheDocument();
    });

    it('hides Allowed IPs when empty', () => {
      const noIpsKey = { ...mockApiKey, allowed_ips: [] };
      render(<ApiKeyDetailsModal {...defaultProps} apiKey={noIpsKey} />);

      expect(screen.queryByText('Allowed IPs')).not.toBeInTheDocument();
    });
  });

  describe('recent activity', () => {
    it('shows Recent Activity section', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Recent Activity')).toBeInTheDocument();
    });

    it('shows table headers', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('Endpoint')).toBeInTheDocument();
      expect(screen.getByText('Method')).toBeInTheDocument();
      expect(screen.getByText('Requests')).toBeInTheDocument();
      expect(screen.getByText('Time')).toBeInTheDocument();
    });

    it('shows endpoint paths', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('/api/v1/accounts')).toBeInTheDocument();
      expect(screen.getByText('/api/v1/billing')).toBeInTheDocument();
      expect(screen.getByText('/api/v1/users')).toBeInTheDocument();
    });

    it('shows HTTP methods', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('GET')).toBeInTheDocument();
      expect(screen.getByText('POST')).toBeInTheDocument();
      expect(screen.getByText('DELETE')).toBeInTheDocument();
    });

    it('shows status codes', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('200')).toBeInTheDocument();
      expect(screen.getByText('201')).toBeInTheDocument();
      expect(screen.getByText('404')).toBeInTheDocument();
    });

    it('shows request counts', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      expect(screen.getByText('150')).toBeInTheDocument();
      expect(screen.getByText('45')).toBeInTheDocument();
      expect(screen.getByText('5')).toBeInTheDocument();
    });

    it('hides Recent Activity when no usage data', () => {
      const noUsageKey = { ...mockApiKey, recent_usage: [] };
      render(<ApiKeyDetailsModal {...defaultProps} apiKey={noUsageKey} />);

      expect(screen.queryByText('Recent Activity')).not.toBeInTheDocument();
    });
  });

  describe('status code styling', () => {
    it('applies success style for 2xx status', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      const successBadge = screen.getByText('200');
      expect(successBadge).toHaveClass('bg-theme-success-background');
    });

    it('applies warning style for 3xx status', () => {
      const keyWith300 = {
        ...mockApiKey,
        recent_usage: [
          { ...mockApiKey.recent_usage[0], status_code: 301 }
        ]
      };
      render(<ApiKeyDetailsModal {...defaultProps} apiKey={keyWith300} />);

      const warningBadge = screen.getByText('301');
      expect(warningBadge).toHaveClass('bg-theme-warning-background');
    });

    it('applies error style for 4xx status', () => {
      render(<ApiKeyDetailsModal {...defaultProps} />);

      const errorBadge = screen.getByText('404');
      expect(errorBadge).toHaveClass('bg-theme-error-background');
    });
  });
});
