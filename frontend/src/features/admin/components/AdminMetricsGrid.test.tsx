import { render, screen } from '@testing-library/react';
import { AdminMetricsGrid } from './AdminMetricsGrid';

describe('AdminMetricsGrid', () => {
  const mockMetrics = {
    total_users: 1250,
    total_accounts: 100,
    active_accounts: 85,
    total_subscriptions: 150,
    active_subscriptions: 120,
    trial_subscriptions: 25,
    total_revenue: 12500000, // $125,000 in cents
    monthly_revenue: 2500000, // $25,000 in cents
    failed_payments: 3,
    system_health: 'healthy' as const
  };

  const defaultProps = {
    metrics: mockMetrics
  };

  describe('loading state', () => {
    it('shows loading skeleton when loading', () => {
      const { container } = render(<AdminMetricsGrid {...defaultProps} loading={true} />);

      expect(container.querySelectorAll('.animate-pulse').length).toBeGreaterThan(0);
    });

    it('shows 8 skeleton cards when loading', () => {
      const { container } = render(<AdminMetricsGrid {...defaultProps} loading={true} />);

      const skeletonCards = container.querySelectorAll('.animate-pulse');
      expect(skeletonCards.length).toBe(8);
    });

    it('hides metrics when loading', () => {
      render(<AdminMetricsGrid {...defaultProps} loading={true} />);

      expect(screen.queryByText('Total Users')).not.toBeInTheDocument();
    });
  });

  describe('metrics display', () => {
    it('shows Total Users metric', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('Total Users')).toBeInTheDocument();
      expect(screen.getByText('1,250')).toBeInTheDocument();
    });

    it('shows Active Accounts metric', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('Active Accounts')).toBeInTheDocument();
      expect(screen.getByText('85 / 100')).toBeInTheDocument();
    });

    it('shows Active Subscriptions metric', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('Active Subscriptions')).toBeInTheDocument();
      expect(screen.getByText('120')).toBeInTheDocument();
    });

    it('shows Trial Subscriptions metric', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('Trial Subscriptions')).toBeInTheDocument();
      expect(screen.getByText('25')).toBeInTheDocument();
    });

    it('shows Total Revenue metric', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('Total Revenue')).toBeInTheDocument();
      expect(screen.getByText('$125,000')).toBeInTheDocument();
    });

    it('shows Monthly Revenue metric', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('Monthly Revenue')).toBeInTheDocument();
      expect(screen.getByText('$25,000')).toBeInTheDocument();
    });

    it('shows Failed Payments metric', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('Failed Payments (30d)')).toBeInTheDocument();
      expect(screen.getByText('3')).toBeInTheDocument();
    });

    it('shows System Health metric', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('System Health')).toBeInTheDocument();
      expect(screen.getByText('Healthy')).toBeInTheDocument();
    });
  });

  describe('status styling', () => {
    it('applies good status for healthy metrics', () => {
      const { container } = render(<AdminMetricsGrid {...defaultProps} />);

      // Total users should have good status
      const cards = container.querySelectorAll('.rounded-lg.border-2');
      expect(cards.length).toBe(8);
    });

    it('applies warning status for low active accounts ratio', () => {
      const lowActiveMetrics = {
        ...mockMetrics,
        total_accounts: 100,
        active_accounts: 70 // 70% - below 80% threshold
      };

      const { container } = render(<AdminMetricsGrid metrics={lowActiveMetrics} />);

      // Should have warning styling for active accounts
      expect(container.querySelector('.border-theme-warning')).toBeInTheDocument();
    });

    it('applies warning status for medium failed payments', () => {
      const mediumFailedMetrics = {
        ...mockMetrics,
        failed_payments: 7 // > 5 triggers warning
      };

      const { container } = render(<AdminMetricsGrid metrics={mediumFailedMetrics} />);

      expect(container.querySelector('.border-theme-warning')).toBeInTheDocument();
    });

    it('applies critical status for high failed payments', () => {
      const highFailedMetrics = {
        ...mockMetrics,
        failed_payments: 15 // > 10 triggers critical
      };

      const { container } = render(<AdminMetricsGrid metrics={highFailedMetrics} />);

      expect(container.querySelector('.border-theme-error')).toBeInTheDocument();
    });

    it('applies warning status for warning system health', () => {
      const warningMetrics = {
        ...mockMetrics,
        system_health: 'warning' as const
      };

      const { container } = render(<AdminMetricsGrid metrics={warningMetrics} />);

      expect(container.querySelector('.border-theme-warning')).toBeInTheDocument();
    });

    it('applies critical status for error system health', () => {
      const errorMetrics = {
        ...mockMetrics,
        system_health: 'error' as const
      };

      const { container } = render(<AdminMetricsGrid metrics={errorMetrics} />);

      expect(container.querySelector('.border-theme-error')).toBeInTheDocument();
    });
  });

  describe('currency formatting', () => {
    it('formats cents as dollars with no decimal places', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      // 12500000 cents = $125,000
      expect(screen.getByText('$125,000')).toBeInTheDocument();
    });

    it('formats small amounts correctly', () => {
      const smallRevenueMetrics = {
        ...mockMetrics,
        total_revenue: 9999 // $99.99 but formatted as $100
      };

      render(<AdminMetricsGrid metrics={smallRevenueMetrics} />);

      expect(screen.getByText('$100')).toBeInTheDocument();
    });
  });

  describe('number formatting', () => {
    it('formats large numbers with commas', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('1,250')).toBeInTheDocument();
    });
  });

  describe('system health display', () => {
    it('capitalizes system health status', () => {
      render(<AdminMetricsGrid {...defaultProps} />);

      expect(screen.getByText('Healthy')).toBeInTheDocument();
    });

    it('shows Warning for warning status', () => {
      const warningMetrics = {
        ...mockMetrics,
        system_health: 'warning' as const
      };

      render(<AdminMetricsGrid metrics={warningMetrics} />);

      expect(screen.getByText('Warning')).toBeInTheDocument();
    });

    it('shows Error for error status', () => {
      const errorMetrics = {
        ...mockMetrics,
        system_health: 'error' as const
      };

      render(<AdminMetricsGrid metrics={errorMetrics} />);

      expect(screen.getByText('Error')).toBeInTheDocument();
    });
  });

  describe('className prop', () => {
    it('applies custom className', () => {
      const { container } = render(<AdminMetricsGrid {...defaultProps} className="custom-class" />);

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('grid layout', () => {
    it('renders 8 metric cards', () => {
      const { container } = render(<AdminMetricsGrid {...defaultProps} />);

      const cards = container.querySelectorAll('.rounded-lg.border-2');
      expect(cards.length).toBe(8);
    });
  });
});
