import { render, screen, fireEvent } from '@testing-library/react';
import { SubscriptionPlanCard } from './SubscriptionPlanCard';
import { Plan } from '@/features/business/plans/services/plansApi';

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, loading, variant, fullWidth }: any) => (
    <button
      onClick={onClick}
      disabled={disabled || loading}
      data-variant={variant}
      data-fullwidth={fullWidth}
      data-loading={loading}
    >
      {children}
    </button>
  )
}));

describe('SubscriptionPlanCard', () => {
  const mockPlan: Plan = {
    id: 'plan-1',
    name: 'Professional',
    description: 'For growing businesses',
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
      advanced_analytics: true,
      custom_integrations: true,
      unlimited_exports: true
    },
    limits: {
      users: 10,
      projects: 50,
      storage: 100
    },
    has_annual_discount: false,
    annual_discount_percent: 0,
    has_promotional_discount: false,
    promotional_discount_percent: 0,
    has_volume_discount: false,
    volume_discount_tiers: []
  };

  const defaultProps = {
    plan: mockPlan,
    onSubscribe: jest.fn(),
    onManage: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('shows plan name', () => {
      render(<SubscriptionPlanCard {...defaultProps} />);

      expect(screen.getByText('Professional')).toBeInTheDocument();
    });

    it('shows formatted price', () => {
      render(<SubscriptionPlanCard {...defaultProps} />);

      expect(screen.getByText('$49.00/month')).toBeInTheDocument();
    });

    it('shows Subscribe button for non-active plans', () => {
      render(<SubscriptionPlanCard {...defaultProps} />);

      expect(screen.getByText('Subscribe')).toBeInTheDocument();
    });

    it('shows feature list', () => {
      render(<SubscriptionPlanCard {...defaultProps} />);

      expect(screen.getByText('10 users')).toBeInTheDocument();
      expect(screen.getByText('50 projects')).toBeInTheDocument();
      expect(screen.getByText('100GB storage')).toBeInTheDocument();
    });

    it('shows limited features and more indicator', () => {
      render(<SubscriptionPlanCard {...defaultProps} />);

      // Should show first 4 features/limits then "+X more"
      expect(screen.getByText(/more features/)).toBeInTheDocument();
    });

    it('shows trial days badge when available', () => {
      render(<SubscriptionPlanCard {...defaultProps} />);

      expect(screen.getByText('14-day free trial')).toBeInTheDocument();
    });
  });

  describe('active state', () => {
    it('shows Current Plan badge when active', () => {
      render(<SubscriptionPlanCard {...defaultProps} isActive={true} />);

      expect(screen.getByText('Current Plan')).toBeInTheDocument();
    });

    it('shows Manage Plan button when active', () => {
      render(<SubscriptionPlanCard {...defaultProps} isActive={true} />);

      expect(screen.getByText('Manage Plan')).toBeInTheDocument();
    });

    it('hides trial badge when active', () => {
      render(<SubscriptionPlanCard {...defaultProps} isActive={true} />);

      expect(screen.queryByText('14-day free trial')).not.toBeInTheDocument();
    });

    it('calls onManage when Manage Plan clicked', () => {
      const onManage = jest.fn();
      render(<SubscriptionPlanCard {...defaultProps} isActive={true} onManage={onManage} />);

      fireEvent.click(screen.getByText('Manage Plan'));

      expect(onManage).toHaveBeenCalledWith('plan-1');
    });
  });

  describe('subscribe functionality', () => {
    it('calls onSubscribe when Subscribe clicked', () => {
      const onSubscribe = jest.fn();
      render(<SubscriptionPlanCard {...defaultProps} onSubscribe={onSubscribe} />);

      fireEvent.click(screen.getByText('Subscribe'));

      expect(onSubscribe).toHaveBeenCalledWith('plan-1');
    });

    it('disables button when loading', () => {
      render(<SubscriptionPlanCard {...defaultProps} loading={true} />);

      expect(screen.getByText('Loading...')).toBeDisabled();
    });
  });

  describe('best value badge', () => {
    it('shows Best Value badge when isBestValue', () => {
      render(<SubscriptionPlanCard {...defaultProps} isBestValue={true} />);

      expect(screen.getByText(/Best Value/)).toBeInTheDocument();
    });
  });

  describe('popular badge', () => {
    it('shows Most Popular badge when isPopular', () => {
      render(<SubscriptionPlanCard {...defaultProps} isPopular={true} />);

      expect(screen.getByText(/Most Popular/)).toBeInTheDocument();
    });
  });

  describe('discount badges', () => {
    it('shows annual discount badge when yearly billing with discount', () => {
      const planWithDiscount = {
        ...mockPlan,
        has_annual_discount: true,
        annual_discount_percent: 20
      };

      render(<SubscriptionPlanCard {...defaultProps} plan={planWithDiscount} billingCycle="yearly" />);

      expect(screen.getByText(/Save 20%/)).toBeInTheDocument();
    });

    it('shows promotional discount badge when active', () => {
      const planWithPromo = {
        ...mockPlan,
        has_promotional_discount: true,
        promotional_discount_percent: 15,
        promotional_discount_start: null,
        promotional_discount_end: null
      };

      render(<SubscriptionPlanCard {...defaultProps} plan={planWithPromo} />);

      expect(screen.getByText(/15% OFF/)).toBeInTheDocument();
    });

    it('shows volume discount badge when available', () => {
      const planWithVolume = {
        ...mockPlan,
        has_volume_discount: true,
        volume_discount_tiers: [
          { min_quantity: 10, discount_percent: 10 },
          { min_quantity: 50, discount_percent: 25 }
        ]
      };

      render(<SubscriptionPlanCard {...defaultProps} plan={planWithVolume} />);

      expect(screen.getByText(/Up to 25% off/)).toBeInTheDocument();
    });
  });

  describe('comparison mode', () => {
    it('shows comparison checkbox when showComparison is true', () => {
      render(<SubscriptionPlanCard {...defaultProps} showComparison={true} onComparisonToggle={jest.fn()} />);

      expect(screen.getByText('Compare')).toBeInTheDocument();
    });

    it('checkbox is checked when isSelectedForComparison', () => {
      render(
        <SubscriptionPlanCard
          {...defaultProps}
          showComparison={true}
          isSelectedForComparison={true}
          onComparisonToggle={jest.fn()}
        />
      );

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toBeChecked();
    });

    it('calls onComparisonToggle when checkbox clicked', () => {
      const onComparisonToggle = jest.fn();
      render(
        <SubscriptionPlanCard
          {...defaultProps}
          showComparison={true}
          onComparisonToggle={onComparisonToggle}
        />
      );

      fireEvent.click(screen.getByRole('checkbox'));

      expect(onComparisonToggle).toHaveBeenCalledWith('plan-1');
    });

    it('hides comparison checkbox when showComparison is false', () => {
      render(<SubscriptionPlanCard {...defaultProps} showComparison={false} />);

      expect(screen.queryByText('Compare')).not.toBeInTheDocument();
    });
  });

  describe('inactive plan status', () => {
    it('shows plan status when not active', () => {
      const inactivePlan = { ...mockPlan, status: 'inactive' as const };
      render(<SubscriptionPlanCard {...defaultProps} plan={inactivePlan} />);

      expect(screen.getByText(/Plan currently inactive/)).toBeInTheDocument();
    });

    it('hides status message for active plans', () => {
      render(<SubscriptionPlanCard {...defaultProps} />);

      expect(screen.queryByText(/Plan currently/)).not.toBeInTheDocument();
    });
  });

  describe('free plans', () => {
    it('shows Free for zero price', () => {
      const freePlan = { ...mockPlan, price_cents: 0 };
      render(<SubscriptionPlanCard {...defaultProps} plan={freePlan} />);

      expect(screen.getByText('Free')).toBeInTheDocument();
    });

    it('shows Free for null price', () => {
      const freePlan = { ...mockPlan, price_cents: null };
      render(<SubscriptionPlanCard {...defaultProps} plan={freePlan as any} />);

      expect(screen.getByText('Free')).toBeInTheDocument();
    });
  });

  describe('billing cycles', () => {
    it('shows yearly price format', () => {
      render(<SubscriptionPlanCard {...defaultProps} billingCycle="yearly" />);

      expect(screen.getByText(/\/year/)).toBeInTheDocument();
    });

    it('shows monthly price format', () => {
      render(<SubscriptionPlanCard {...defaultProps} billingCycle="monthly" />);

      expect(screen.getByText(/\/month/)).toBeInTheDocument();
    });
  });

  describe('original price with discount', () => {
    it('shows strikethrough original price when discounted', () => {
      const planWithDiscount = {
        ...mockPlan,
        has_annual_discount: true,
        annual_discount_percent: 20
      };

      render(<SubscriptionPlanCard {...defaultProps} plan={planWithDiscount} billingCycle="yearly" />);

      expect(screen.getByText(/saved/)).toBeInTheDocument();
    });
  });
});
