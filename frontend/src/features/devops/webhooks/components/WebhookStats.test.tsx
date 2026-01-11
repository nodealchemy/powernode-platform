import { render, screen } from '@testing-library/react';
import { WebhookStats } from './WebhookStats';

describe('WebhookStats', () => {
  const mockStats = {
    total_endpoints: 10,
    active_endpoints: 8,
    inactive_endpoints: 2,
    total_deliveries_today: 500,
    successful_deliveries_today: 480,
    failed_deliveries_today: 20
  };

  const mockDetailedStats = {
    // Base WebhookStats properties
    total_endpoints: 10,
    active_endpoints: 8,
    inactive_endpoints: 2,
    total_deliveries_today: 500,
    successful_deliveries_today: 480,
    failed_deliveries_today: 20,
    // DetailedWebhookStats extended properties
    average_response_times: 245.5,
    retry_statistics: {
      total_retries: 50,
      pending_retries: 5,
      max_retries_reached: 2
    },
    most_active_endpoints: {
      'https://api.example.com/webhook1': 100,
      'https://api.example.com/webhook2': 80
    },
    event_type_distribution: {
      'order.created': 200,
      'payment.completed': 150
    },
    daily_delivery_trend: {
      '2024-01-01': 100,
      '2024-01-02': 120
    }
  };

  describe('loading state', () => {
    it('shows loading spinner when loading', () => {
      render(<WebhookStats stats={null} detailedStats={null} loading={true} />);

      // LoadingSpinner should be visible
      const loadingContainer = document.querySelector('.flex.justify-center');
      expect(loadingContainer).toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows empty message when no stats', () => {
      render(<WebhookStats stats={null} detailedStats={null} loading={false} />);

      expect(screen.getByText('No statistics available')).toBeInTheDocument();
      expect(screen.getByText(/Statistics will appear here/)).toBeInTheDocument();
    });
  });

  describe('basic stats', () => {
    it('displays total endpoints', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('10')).toBeInTheDocument();
      expect(screen.getByText('Total Endpoints')).toBeInTheDocument();
    });

    it('displays active endpoints', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('8')).toBeInTheDocument();
      expect(screen.getByText('Active')).toBeInTheDocument();
    });

    it('displays inactive endpoints', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('2')).toBeInTheDocument();
      expect(screen.getByText('Inactive')).toBeInTheDocument();
    });

    it('displays deliveries today', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('500')).toBeInTheDocument();
      expect(screen.getByText('Deliveries Today')).toBeInTheDocument();
    });

    it('displays successful deliveries', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('480')).toBeInTheDocument();
      expect(screen.getByText('Successful')).toBeInTheDocument();
    });

    it('displays failed deliveries', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('20')).toBeInTheDocument();
      expect(screen.getByText('Failed')).toBeInTheDocument();
    });
  });

  describe('success rate', () => {
    it('calculates and displays success rate', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      // 480/500 = 96%
      expect(screen.getByText('96%')).toBeInTheDocument();
      expect(screen.getByText('Success Rate Today')).toBeInTheDocument();
    });

    it('shows 0% when no deliveries', () => {
      const emptyStats = {
        ...mockStats,
        successful_deliveries_today: 0,
        failed_deliveries_today: 0
      };
      render(<WebhookStats stats={emptyStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('0%')).toBeInTheDocument();
    });

    it('shows success/failed counts in success rate section', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('480 successful')).toBeInTheDocument();
      expect(screen.getByText('20 failed')).toBeInTheDocument();
    });
  });

  describe('detailed stats', () => {
    it('displays average response time', () => {
      render(<WebhookStats stats={mockStats} detailedStats={mockDetailedStats} loading={false} />);

      expect(screen.getByText('Performance')).toBeInTheDocument();
      expect(screen.getByText('246ms')).toBeInTheDocument();
    });

    it('displays retry statistics', () => {
      render(<WebhookStats stats={mockStats} detailedStats={mockDetailedStats} loading={false} />);

      expect(screen.getByText('Retry Statistics')).toBeInTheDocument();
      expect(screen.getByText('Total Retries')).toBeInTheDocument();
      expect(screen.getByText('50')).toBeInTheDocument();
      expect(screen.getByText('Pending Retries')).toBeInTheDocument();
      expect(screen.getByText('5')).toBeInTheDocument();
      expect(screen.getByText('Max Retries Reached')).toBeInTheDocument();
    });

    it('displays most active endpoints', () => {
      render(<WebhookStats stats={mockStats} detailedStats={mockDetailedStats} loading={false} />);

      expect(screen.getByText('Most Active Endpoints')).toBeInTheDocument();
      expect(screen.getByText(/webhook1/)).toBeInTheDocument();
      expect(screen.getByText('100')).toBeInTheDocument();
    });

    it('displays event type distribution', () => {
      render(<WebhookStats stats={mockStats} detailedStats={mockDetailedStats} loading={false} />);

      expect(screen.getByText('Event Type Distribution (Last 7 Days)')).toBeInTheDocument();
    });

    it('displays daily delivery trend', () => {
      render(<WebhookStats stats={mockStats} detailedStats={mockDetailedStats} loading={false} />);

      expect(screen.getByText('Daily Delivery Trend (Last 7 Days)')).toBeInTheDocument();
    });
  });

  describe('health summary', () => {
    it('displays webhook health summary', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('Webhook Health Summary')).toBeInTheDocument();
      expect(screen.getByText('Overall Status')).toBeInTheDocument();
    });

    it('shows active endpoint count in summary', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText(/8 active endpoints/)).toBeInTheDocument();
    });

    it('shows success rate in summary', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText(/96% success rate today/)).toBeInTheDocument();
    });

    it('shows recommendations when there are failures', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText('Recommendations')).toBeInTheDocument();
      expect(screen.getByText(/Review failed deliveries/)).toBeInTheDocument();
    });

    it('shows inactive endpoint recommendation', () => {
      render(<WebhookStats stats={mockStats} detailedStats={null} loading={false} />);

      expect(screen.getByText(/Consider activating inactive endpoints/)).toBeInTheDocument();
    });
  });

  describe('empty detailed stats sections', () => {
    it('shows no activity message for empty active endpoints', () => {
      const emptyDetailedStats = {
        ...mockDetailedStats,
        most_active_endpoints: {}
      };
      render(<WebhookStats stats={mockStats} detailedStats={emptyDetailedStats} loading={false} />);

      expect(screen.getByText('No activity data available')).toBeInTheDocument();
    });

    it('shows no event data message for empty event distribution', () => {
      const emptyDetailedStats = {
        ...mockDetailedStats,
        event_type_distribution: {}
      };
      render(<WebhookStats stats={mockStats} detailedStats={emptyDetailedStats} loading={false} />);

      expect(screen.getByText('No event data available')).toBeInTheDocument();
    });

    it('shows no delivery trend message for empty trend', () => {
      const emptyDetailedStats = {
        ...mockDetailedStats,
        daily_delivery_trend: {}
      };
      render(<WebhookStats stats={mockStats} detailedStats={emptyDetailedStats} loading={false} />);

      expect(screen.getByText('No delivery trend data available')).toBeInTheDocument();
    });
  });
});
