import { render, screen, fireEvent } from '@testing-library/react';
import { AdminSystemHealth } from './AdminSystemHealth';

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, variant, disabled }: any) => (
    <button onClick={onClick} data-variant={variant} disabled={disabled}>
      {children}
    </button>
  )
}));

describe('AdminSystemHealth', () => {
  const mockPaymentGateways = {
    stripe: {
      connected: true,
      environment: 'production',
      webhook_status: 'healthy' as const,
      last_webhook: '2025-01-15T10:00:00Z'
    },
    paypal: {
      connected: true,
      environment: 'sandbox',
      webhook_status: 'warning' as const,
      last_webhook: '2025-01-15T09:30:00Z'
    }
  };

  const defaultProps = {
    systemHealth: 'healthy' as const,
    uptime: 86400 * 5 + 3600 * 2 + 60 * 30, // 5d 2h 30m
    paymentGateways: mockPaymentGateways
  };

  describe('loading state', () => {
    it('shows loading skeleton when loading', () => {
      const { container } = render(<AdminSystemHealth {...defaultProps} loading={true} />);

      expect(container.querySelector('.animate-pulse')).toBeInTheDocument();
    });

    it('hides content when loading', () => {
      render(<AdminSystemHealth {...defaultProps} loading={true} />);

      expect(screen.queryByText('System Health')).not.toBeInTheDocument();
    });
  });

  describe('header', () => {
    it('shows System Health title', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('System Health')).toBeInTheDocument();
    });

    it('shows formatted uptime', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Uptime: 5d 2h 30m')).toBeInTheDocument();
    });

    it('shows refresh button when onRefresh provided', () => {
      render(<AdminSystemHealth {...defaultProps} onRefresh={jest.fn()} />);

      expect(screen.getByRole('button')).toBeInTheDocument();
    });

    it('calls onRefresh when refresh clicked', () => {
      const onRefresh = jest.fn();
      render(<AdminSystemHealth {...defaultProps} onRefresh={onRefresh} />);

      fireEvent.click(screen.getByRole('button'));

      expect(onRefresh).toHaveBeenCalled();
    });

    it('hides refresh button when onRefresh not provided', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.queryByRole('button')).not.toBeInTheDocument();
    });
  });

  describe('overall status', () => {
    it('shows All Systems Operational for healthy status', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('All Systems Operational')).toBeInTheDocument();
    });

    it('shows Degraded Performance for warning status', () => {
      render(<AdminSystemHealth {...defaultProps} systemHealth="warning" />);

      expect(screen.getByText('Degraded Performance')).toBeInTheDocument();
    });

    it('shows System Issues Detected for error status', () => {
      render(<AdminSystemHealth {...defaultProps} systemHealth="error" />);

      expect(screen.getByText('System Issues Detected')).toBeInTheDocument();
    });

    it('shows component count', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('6 of 6 components operational')).toBeInTheDocument();
    });
  });

  describe('system components', () => {
    it('shows System Components section', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('System Components')).toBeInTheDocument();
    });

    it('shows API Server component', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('API Server')).toBeInTheDocument();
      expect(screen.getByText('Core API services')).toBeInTheDocument();
    });

    it('shows Database component', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Database')).toBeInTheDocument();
      expect(screen.getByText('PostgreSQL database')).toBeInTheDocument();
    });

    it('shows Background Workers component', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Background Workers')).toBeInTheDocument();
      expect(screen.getByText('Sidekiq job processing')).toBeInTheDocument();
    });

    it('shows Cache component', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Cache')).toBeInTheDocument();
      expect(screen.getByText('Redis cache layer')).toBeInTheDocument();
    });

    it('shows Storage component', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Storage')).toBeInTheDocument();
      expect(screen.getByText('File storage services')).toBeInTheDocument();
    });

    it('shows Email Service component', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Email Service')).toBeInTheDocument();
      expect(screen.getByText('Email delivery')).toBeInTheDocument();
    });
  });

  describe('payment gateways section', () => {
    it('shows Payment Gateways title', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Payment Gateways')).toBeInTheDocument();
    });

    it('shows Stripe gateway', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Stripe')).toBeInTheDocument();
    });

    it('shows PayPal gateway', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('PayPal')).toBeInTheDocument();
    });

    it('shows Stripe environment', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('production')).toBeInTheDocument();
    });

    it('shows PayPal environment', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('sandbox')).toBeInTheDocument();
    });

    it('shows Webhook Status labels', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      const webhookLabels = screen.getAllByText('Webhook Status');
      expect(webhookLabels.length).toBe(2);
    });

    it('shows Environment labels', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      const envLabels = screen.getAllByText('Environment');
      expect(envLabels.length).toBe(2);
    });

    it('shows Operational badge for connected gateways', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      const operationalBadges = screen.getAllByText('Operational');
      expect(operationalBadges.length).toBe(2);
    });

    it('shows Major Outage badge for disconnected gateway', () => {
      const disconnectedGateways = {
        ...mockPaymentGateways,
        stripe: { ...mockPaymentGateways.stripe, connected: false }
      };

      render(<AdminSystemHealth {...defaultProps} paymentGateways={disconnectedGateways} />);

      expect(screen.getByText('Major Outage')).toBeInTheDocument();
    });

    it('shows webhook status badges', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Healthy')).toBeInTheDocument();
      expect(screen.getByText('Warning')).toBeInTheDocument();
    });
  });

  describe('uptime formatting', () => {
    it('formats days and hours correctly', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Uptime: 5d 2h 30m')).toBeInTheDocument();
    });

    it('formats hours only when less than a day', () => {
      const shortUptime = 3600 * 5 + 60 * 15; // 5h 15m

      render(<AdminSystemHealth {...defaultProps} uptime={shortUptime} />);

      expect(screen.getByText('Uptime: 5h 15m')).toBeInTheDocument();
    });

    it('formats minutes only when less than an hour', () => {
      const veryShortUptime = 60 * 45; // 45m

      render(<AdminSystemHealth {...defaultProps} uptime={veryShortUptime} />);

      expect(screen.getByText('Uptime: 45m')).toBeInTheDocument();
    });

    it('shows 0m for zero uptime', () => {
      render(<AdminSystemHealth {...defaultProps} uptime={0} />);

      expect(screen.getByText('Uptime: 0m')).toBeInTheDocument();
    });
  });

  describe('status badge styling', () => {
    it('shows Healthy badge for healthy webhook', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Healthy')).toBeInTheDocument();
    });

    it('shows Warning badge for warning webhook', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      expect(screen.getByText('Warning')).toBeInTheDocument();
    });

    it('shows Unhealthy badge for unhealthy webhook', () => {
      const unhealthyGateways = {
        ...mockPaymentGateways,
        stripe: { ...mockPaymentGateways.stripe, webhook_status: 'unhealthy' as const }
      };

      render(<AdminSystemHealth {...defaultProps} paymentGateways={unhealthyGateways} />);

      expect(screen.getByText('Unhealthy')).toBeInTheDocument();
    });

    it('shows No Data badge for no_data webhook', () => {
      const noDataGateways = {
        ...mockPaymentGateways,
        stripe: { ...mockPaymentGateways.stripe, webhook_status: 'no_data' as const }
      };

      render(<AdminSystemHealth {...defaultProps} paymentGateways={noDataGateways} />);

      expect(screen.getByText('No Data')).toBeInTheDocument();
    });
  });

  describe('last webhook display', () => {
    it('shows Last Webhook labels', () => {
      render(<AdminSystemHealth {...defaultProps} />);

      const lastWebhookLabels = screen.getAllByText('Last Webhook');
      expect(lastWebhookLabels.length).toBe(2);
    });

    it('hides Last Webhook when null', () => {
      const noLastWebhookGateways = {
        ...mockPaymentGateways,
        stripe: { ...mockPaymentGateways.stripe, last_webhook: null }
      };

      render(<AdminSystemHealth {...defaultProps} paymentGateways={noLastWebhookGateways} />);

      const lastWebhookLabels = screen.getAllByText('Last Webhook');
      expect(lastWebhookLabels.length).toBe(1); // Only PayPal shows
    });
  });

  describe('className prop', () => {
    it('applies custom className', () => {
      const { container } = render(<AdminSystemHealth {...defaultProps} className="custom-class" />);

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });
});
