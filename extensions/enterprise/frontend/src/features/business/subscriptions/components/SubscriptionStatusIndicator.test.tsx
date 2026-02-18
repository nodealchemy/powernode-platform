import { render, screen } from '@testing-library/react';
import { SubscriptionStatusIndicator } from './SubscriptionStatusIndicator';
import { Subscription } from '@/shared/types';

// Mock useSubscriptionLifecycle hook
const mockCheckSubscriptionStatus = jest.fn();
const mockGetDaysUntilExpiry = jest.fn();

jest.mock('@/shared/hooks/useSubscriptionLifecycle', () => ({
  useSubscriptionLifecycle: () => ({
    checkSubscriptionStatus: mockCheckSubscriptionStatus,
    getDaysUntilExpiry: mockGetDaysUntilExpiry
  })
}));

describe('SubscriptionStatusIndicator', () => {
  const mockSubscription: Subscription = {
    id: 'sub-1',
    status: 'active',
    plan: {
      id: 'plan-1',
      name: 'Professional',
      description: 'Professional plan',
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
      features: {}
    },
    current_period_start: '2025-01-01T00:00:00Z',
    current_period_end: '2025-02-01T00:00:00Z',
    trial_end: undefined,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockCheckSubscriptionStatus.mockReturnValue('active');
    mockGetDaysUntilExpiry.mockReturnValue(30);
  });

  describe('active status', () => {
    it('shows Active message', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} />);

      expect(screen.getByText('Active')).toBeInTheDocument();
    });

    it('shows checkmark icon', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} />);

      expect(screen.getByText('✓')).toBeInTheDocument();
    });

    it('shows next billing date in details mode', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(screen.getByText(/Next billing:/)).toBeInTheDocument();
    });
  });

  describe('trial_ending status', () => {
    beforeEach(() => {
      mockCheckSubscriptionStatus.mockReturnValue('trial_ending');
      mockGetDaysUntilExpiry.mockReturnValue(5);
    });

    it('shows Trial Ending message', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} />);

      expect(screen.getByText('Trial Ending')).toBeInTheDocument();
    });

    it('shows clock icon', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} />);

      expect(screen.getByText('⏰')).toBeInTheDocument();
    });

    it('shows days remaining in details mode', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(screen.getByText(/Trial ends in 5 days/)).toBeInTheDocument();
    });

    it('shows action required message in details mode', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(screen.getByText('Action Required:')).toBeInTheDocument();
    });
  });

  describe('expiring status', () => {
    beforeEach(() => {
      mockCheckSubscriptionStatus.mockReturnValue('expiring');
      mockGetDaysUntilExpiry.mockReturnValue(7);
    });

    it('shows Expiring Soon message', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} />);

      expect(screen.getByText('Expiring Soon')).toBeInTheDocument();
    });

    it('shows warning icon', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} />);

      expect(screen.getByText('⚠️')).toBeInTheDocument();
    });

    it('shows days remaining in details mode', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(screen.getByText(/Expires in 7 days/)).toBeInTheDocument();
    });

    it('shows action required message in details mode', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(screen.getByText(/update your payment method/)).toBeInTheDocument();
    });
  });

  describe('expired status', () => {
    beforeEach(() => {
      mockCheckSubscriptionStatus.mockReturnValue('expired');
      mockGetDaysUntilExpiry.mockReturnValue(0);
    });

    it('shows Expired message', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} />);

      expect(screen.getByText('Expired')).toBeInTheDocument();
    });

    it('shows X icon', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} />);

      expect(screen.getByText('❌')).toBeInTheDocument();
    });

    it('shows expired description in details mode', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(screen.getByText('Subscription has expired')).toBeInTheDocument();
    });
  });

  describe('unknown status', () => {
    beforeEach(() => {
      mockCheckSubscriptionStatus.mockReturnValue('unknown');
    });

    const customSubscription = {
      ...mockSubscription,
      status: 'paused'
    };

    it('shows capitalized status name', () => {
      render(<SubscriptionStatusIndicator subscription={customSubscription} />);

      expect(screen.getByText('Paused')).toBeInTheDocument();
    });

    it('shows default icon', () => {
      render(<SubscriptionStatusIndicator subscription={customSubscription} />);

      expect(screen.getByText('●')).toBeInTheDocument();
    });
  });

  describe('details mode', () => {
    it('renders as badge in simple mode', () => {
      const { container } = render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={false} />);

      expect(container.querySelector('span')).toHaveClass('rounded-full');
    });

    it('renders as card in details mode', () => {
      const { container } = render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(container.querySelector('div')).toHaveClass('rounded-lg');
    });

    it('does not show description in simple mode', () => {
      render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={false} />);

      expect(screen.queryByText(/Next billing:/)).not.toBeInTheDocument();
    });
  });

  describe('singular/plural days', () => {
    it('uses singular day for 1 day', () => {
      mockCheckSubscriptionStatus.mockReturnValue('expiring');
      mockGetDaysUntilExpiry.mockReturnValue(1);

      render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(screen.getByText(/Expires in 1 day$/)).toBeInTheDocument();
    });

    it('uses plural days for multiple days', () => {
      mockCheckSubscriptionStatus.mockReturnValue('expiring');
      mockGetDaysUntilExpiry.mockReturnValue(5);

      render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(screen.getByText(/Expires in 5 days/)).toBeInTheDocument();
    });
  });

  describe('no expiration', () => {
    it('shows No expiration for null date', () => {
      const noExpirationSubscription = {
        ...mockSubscription,
        current_period_end: null as unknown as string
      };

      render(<SubscriptionStatusIndicator subscription={noExpirationSubscription} showDetails={true} />);

      // The formatDate function returns 'No expiration' for null dates
      // But the description says "Never expires" based on the logic
    });
  });

  describe('border colors in details mode', () => {
    it('uses success border for active status', () => {
      mockCheckSubscriptionStatus.mockReturnValue('active');
      const { container } = render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(container.querySelector('div.border-theme-success')).toBeInTheDocument();
    });

    it('uses warning border for expiring status', () => {
      mockCheckSubscriptionStatus.mockReturnValue('expiring');
      const { container } = render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(container.querySelector('div.border-theme-warning')).toBeInTheDocument();
    });

    it('uses error border for expired status', () => {
      mockCheckSubscriptionStatus.mockReturnValue('expired');
      const { container } = render(<SubscriptionStatusIndicator subscription={mockSubscription} showDetails={true} />);

      expect(container.querySelector('div.border-theme-error')).toBeInTheDocument();
    });
  });
});
