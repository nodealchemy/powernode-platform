import { render, screen, fireEvent } from '@testing-library/react';
import { CurrentPlanSummary } from './CurrentPlanSummary';
import { Subscription } from '@/shared/types';

// Mock SubscriptionStatusIndicator
jest.mock('./SubscriptionStatusIndicator', () => ({
  SubscriptionStatusIndicator: ({ subscription, showDetails }: any) => (
    <div data-testid="status-indicator" data-show-details={showDetails}>
      {subscription.status}
    </div>
  )
}));

describe('CurrentPlanSummary', () => {
  const mockSubscription: Subscription = {
    id: 'sub-1',
    status: 'active',
    plan: {
      id: 'plan-1',
      name: 'Professional',
      description: 'Professional plan for growing teams',
      price_cents: 4900,
      currency: 'USD',
      billing_cycle: 'monthly',
      status: 'active',
      trial_days: 14,
      is_public: true,
      formatted_price: '$49.00',
      monthly_price: '$49.00',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      features: {
        api_access: true,
        priority_support: true,
        advanced_analytics: true
      }
    },
    current_period_start: '2025-01-01T00:00:00Z',
    current_period_end: '2025-02-01T00:00:00Z',
    trial_end: undefined,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  const defaultProps = {
    subscription: mockSubscription,
    loading: false,
    onManage: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    // Mock current date
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2025-01-15T00:00:00Z'));
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('loading state', () => {
    it('shows loading skeleton when loading', () => {
      const { container } = render(<CurrentPlanSummary {...defaultProps} loading={true} />);

      expect(container.querySelector('.animate-pulse')).toBeInTheDocument();
    });
  });

  describe('no subscription state', () => {
    it('shows no subscription message', () => {
      render(<CurrentPlanSummary {...defaultProps} subscription={null} />);

      expect(screen.getByText('No Active Subscription')).toBeInTheDocument();
    });

    it('shows get started message', () => {
      render(<CurrentPlanSummary {...defaultProps} subscription={null} />);

      expect(screen.getByText(/Choose a plan below/)).toBeInTheDocument();
    });

    it('shows Browse Plans button when onManage provided', () => {
      render(<CurrentPlanSummary {...defaultProps} subscription={null} />);

      expect(screen.getByText('Browse Plans')).toBeInTheDocument();
    });

    it('calls onManage when Browse Plans clicked', () => {
      const onManage = jest.fn();
      render(<CurrentPlanSummary {...defaultProps} subscription={null} onManage={onManage} />);

      fireEvent.click(screen.getByText('Browse Plans'));

      expect(onManage).toHaveBeenCalled();
    });
  });

  describe('active subscription', () => {
    it('shows Current Plan title', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByText('Current Plan')).toBeInTheDocument();
    });

    it('shows plan name', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByText('Professional')).toBeInTheDocument();
    });

    it('shows formatted price', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByText('$49.00/monthly')).toBeInTheDocument();
    });

    it('shows billing cycle', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByText('monthly billing')).toBeInTheDocument();
    });

    it('shows status indicator', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByTestId('status-indicator')).toBeInTheDocument();
    });

    it('shows Next Billing label for active subscription', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByText('Next Billing')).toBeInTheDocument();
    });

    it('shows Days Remaining', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByText('Days Remaining')).toBeInTheDocument();
    });

    it('calculates days remaining correctly', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      // From Jan 15 to Feb 1 = 17 days
      expect(screen.getByText(/17 days/)).toBeInTheDocument();
    });

    it('shows until renewal text', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByText(/until renewal/)).toBeInTheDocument();
    });
  });

  describe('trial subscription', () => {
    const trialSubscription = {
      ...mockSubscription,
      status: 'trialing',
      trial_end: '2025-01-20T00:00:00Z'
    };

    it('shows Trial Ends label', () => {
      render(<CurrentPlanSummary {...defaultProps} subscription={trialSubscription} />);

      expect(screen.getByText('Trial Ends')).toBeInTheDocument();
    });

    it('shows in trial text', () => {
      render(<CurrentPlanSummary {...defaultProps} subscription={trialSubscription} />);

      expect(screen.getByText(/in trial/)).toBeInTheDocument();
    });

    it('shows trial ending warning when 7 days or less', () => {
      const endingTrialSubscription = {
        ...trialSubscription,
        trial_end: '2025-01-20T00:00:00Z',
        current_period_end: '2025-01-20T00:00:00Z' // 5 days from mock date - triggers warning
      };

      render(<CurrentPlanSummary {...defaultProps} subscription={endingTrialSubscription} />);

      expect(screen.getByText('Trial ending soon!')).toBeInTheDocument();
    });

    it('shows upgrade prompt in warning', () => {
      const endingTrialSubscription = {
        ...trialSubscription,
        trial_end: '2025-01-20T00:00:00Z',
        current_period_end: '2025-01-20T00:00:00Z' // 5 days from mock date - triggers warning
      };

      render(<CurrentPlanSummary {...defaultProps} subscription={endingTrialSubscription} />);

      expect(screen.getByText(/Choose a plan to continue/)).toBeInTheDocument();
    });
  });

  describe('features display', () => {
    it('shows Key Features label', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByText('Key Features:')).toBeInTheDocument();
    });

    it('displays feature names', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      // Features get formatted with underscores replaced and capitalized
      expect(screen.getByText('Api Access')).toBeInTheDocument();
    });
  });

  describe('manage subscription button', () => {
    it('shows Manage Subscription button', () => {
      render(<CurrentPlanSummary {...defaultProps} />);

      expect(screen.getByText('Manage Subscription')).toBeInTheDocument();
    });

    it('calls onManage when clicked', () => {
      const onManage = jest.fn();
      render(<CurrentPlanSummary {...defaultProps} onManage={onManage} />);

      fireEvent.click(screen.getByText('Manage Subscription'));

      expect(onManage).toHaveBeenCalled();
    });

    it('hides button when onManage not provided', () => {
      render(<CurrentPlanSummary {...defaultProps} onManage={undefined} />);

      expect(screen.queryByText('Manage Subscription')).not.toBeInTheDocument();
    });
  });

  describe('free plan', () => {
    it('shows Free for zero price', () => {
      const freeSubscription = {
        ...mockSubscription,
        plan: { ...mockSubscription.plan, price_cents: 0 }
      };

      render(<CurrentPlanSummary {...defaultProps} subscription={freeSubscription} />);

      expect(screen.getByText('Free')).toBeInTheDocument();
    });
  });

  describe('date formatting', () => {
    it('shows Never expires for null dates', () => {
      const neverExpiresSubscription = {
        ...mockSubscription,
        current_period_end: null as unknown as string
      };

      render(<CurrentPlanSummary {...defaultProps} subscription={neverExpiresSubscription} />);

      expect(screen.getByText('Never expires')).toBeInTheDocument();
    });
  });

  describe('className prop', () => {
    it('applies custom className', () => {
      const { container } = render(<CurrentPlanSummary {...defaultProps} className="custom-class" />);

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });
});
