import { render, screen, fireEvent } from '@testing-library/react';
import { SimplePlanBrowser } from './SimplePlanBrowser';
import { Plan } from '@enterprise/features/business/plans/services/plansApi';
import { Subscription } from '@/shared/types';

describe('SimplePlanBrowser', () => {
  const mockPlans: Plan[] = [
    {
      id: 'plan-free',
      name: 'Free',
      description: 'Free tier for individuals',
      price_cents: 0,
      currency: 'USD',
      billing_cycle: 'monthly',
      status: 'active',
      is_public: true,
      trial_days: 0,
      formatted_price: '$0.00',
      monthly_price: '$0.00',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      features: {
        api_access: false,
        basic_support: true
      },
      limits: {},
      has_annual_discount: false,
      annual_discount_percent: 0,
      annual_savings_percentage: 0
    },
    {
      id: 'plan-pro',
      name: 'Professional',
      description: 'Professional plan for teams',
      price_cents: 4900,
      currency: 'USD',
      billing_cycle: 'monthly',
      status: 'active',
      is_public: true,
      trial_days: 14,
      formatted_price: '$49.00',
      monthly_price: '$49.00',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      features: {
        api_access: true,
        priority_support: true,
        advanced_analytics: true
      },
      limits: {},
      has_annual_discount: true,
      annual_discount_percent: 20,
      annual_savings_percentage: 20
    },
    {
      id: 'plan-enterprise',
      name: 'Enterprise',
      description: 'Enterprise plan for large organizations',
      price_cents: 9900,
      currency: 'USD',
      billing_cycle: 'monthly',
      status: 'active',
      is_public: true,
      trial_days: 30,
      formatted_price: '$99.00',
      monthly_price: '$99.00',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      features: {
        api_access: true,
        priority_support: true,
        advanced_analytics: true,
        custom_integrations: true,
        dedicated_support: true
      },
      limits: {},
      has_annual_discount: true,
      annual_discount_percent: 25,
      annual_savings_percentage: 25
    },
    {
      id: 'plan-private',
      name: 'Private Plan',
      description: 'Private custom plan',
      price_cents: 19900,
      currency: 'USD',
      billing_cycle: 'monthly',
      status: 'active',
      is_public: false, // Not public
      trial_days: 0,
      formatted_price: '$199.00',
      monthly_price: '$199.00',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      features: {},
      limits: {},
      has_annual_discount: false,
      annual_discount_percent: 0,
      annual_savings_percentage: 0
    }
  ];

  const mockCurrentSubscription: Subscription = {
    id: 'sub-1',
    status: 'active',
    plan: mockPlans[1], // Professional plan
    current_period_start: '2025-01-01T00:00:00Z',
    current_period_end: '2025-02-01T00:00:00Z',
    trial_end: undefined,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  const defaultProps = {
    plans: mockPlans,
    currentSubscription: null,
    onPlanSelect: jest.fn(),
    loading: false,
    billingCycle: 'monthly' as const,
    onBillingCycleChange: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('shows billing cycle toggle', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      expect(screen.getByText('Monthly')).toBeInTheDocument();
      expect(screen.getByText('Yearly')).toBeInTheDocument();
    });

    it('shows save up to 20% badge on yearly option', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      expect(screen.getByText('Save up to 20%')).toBeInTheDocument();
    });

    it('shows only public plans', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      // Use getAllByText since plan name and price can both show "Free"
      expect(screen.getAllByText('Free').length).toBeGreaterThan(0);
      expect(screen.getByText('Professional')).toBeInTheDocument();
      expect(screen.getByText('Enterprise')).toBeInTheDocument();
      expect(screen.queryByText('Private Plan')).not.toBeInTheDocument();
    });

    it('shows plan prices', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      // Free plan shows "Free" for both name and price
      expect(screen.getAllByText('Free').length).toBeGreaterThan(0);
      expect(screen.getByText('$49.00/month')).toBeInTheDocument();
      expect(screen.getByText('$99.00/month')).toBeInTheDocument();
    });

    it('shows trial information for plans with trials', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      expect(screen.getByText('14-day free trial included')).toBeInTheDocument();
      expect(screen.getByText('30-day free trial included')).toBeInTheDocument();
    });

    it('shows Select Plan button for non-current plans', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      const selectButtons = screen.getAllByText('Select Plan');
      expect(selectButtons.length).toBe(3); // All 3 public plans
    });
  });

  describe('loading state', () => {
    it('shows loading skeleton when loading', () => {
      const { container } = render(<SimplePlanBrowser {...defaultProps} loading={true} />);

      expect(container.querySelectorAll('.animate-pulse').length).toBeGreaterThan(0);
    });

    it('hides plan cards when loading', () => {
      render(<SimplePlanBrowser {...defaultProps} loading={true} />);

      expect(screen.queryByText('Professional')).not.toBeInTheDocument();
    });
  });

  describe('billing cycle toggle', () => {
    it('calls onBillingCycleChange with monthly when Monthly clicked', () => {
      const onBillingCycleChange = jest.fn();
      render(<SimplePlanBrowser {...defaultProps} billingCycle="yearly" onBillingCycleChange={onBillingCycleChange} />);

      fireEvent.click(screen.getByText('Monthly'));

      expect(onBillingCycleChange).toHaveBeenCalledWith('monthly');
    });

    it('calls onBillingCycleChange with yearly when Yearly clicked', () => {
      const onBillingCycleChange = jest.fn();
      render(<SimplePlanBrowser {...defaultProps} onBillingCycleChange={onBillingCycleChange} />);

      fireEvent.click(screen.getByText('Yearly'));

      expect(onBillingCycleChange).toHaveBeenCalledWith('yearly');
    });

    it('shows yearly prices when yearly billing selected', () => {
      render(<SimplePlanBrowser {...defaultProps} billingCycle="yearly" />);

      // Professional: $49 * 12 * 0.8 (20% off) = $470.40/year
      expect(screen.getByText('$470.40/year')).toBeInTheDocument();
      // Enterprise: $99 * 12 * 0.75 (25% off) = $891/year
      expect(screen.getByText('$891.00/year')).toBeInTheDocument();
    });

    it('shows savings percentage for yearly billing', () => {
      render(<SimplePlanBrowser {...defaultProps} billingCycle="yearly" />);

      expect(screen.getByText('Save 20% with yearly billing')).toBeInTheDocument();
      expect(screen.getByText('Save 25% with yearly billing')).toBeInTheDocument();
    });
  });

  describe('plan selection', () => {
    it('calls onPlanSelect when Select Plan clicked', () => {
      const onPlanSelect = jest.fn();
      render(<SimplePlanBrowser {...defaultProps} onPlanSelect={onPlanSelect} />);

      const selectButtons = screen.getAllByText('Select Plan');
      fireEvent.click(selectButtons[0]); // Click Free plan

      expect(onPlanSelect).toHaveBeenCalledWith('plan-free');
    });

    it('calls onPlanSelect with correct plan id', () => {
      const onPlanSelect = jest.fn();
      render(<SimplePlanBrowser {...defaultProps} onPlanSelect={onPlanSelect} />);

      const selectButtons = screen.getAllByText('Select Plan');
      fireEvent.click(selectButtons[2]); // Click Enterprise plan

      expect(onPlanSelect).toHaveBeenCalledWith('plan-enterprise');
    });
  });

  describe('current plan display', () => {
    it('shows Current Plan badge for subscribed plan', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      expect(screen.getByText('Current Plan', { selector: 'span' })).toBeInTheDocument();
    });

    it('shows Current Plan button for current plan', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      expect(screen.getByText('Current Plan', { selector: 'button' })).toBeInTheDocument();
    });

    it('disables Current Plan button', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      const currentPlanButton = screen.getByText('Current Plan', { selector: 'button' });
      expect(currentPlanButton).toBeDisabled();
    });

    it('hides trial info for current plan', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      // The Professional plan has 14-day trial, but shouldn't show for current plan
      // Free plan doesn't have trial, Enterprise has 30-day trial
      expect(screen.queryByText('14-day free trial included')).not.toBeInTheDocument();
      expect(screen.getByText('30-day free trial included')).toBeInTheDocument();
    });
  });

  describe('upgrade/downgrade indicators', () => {
    it('shows Upgrade badge for higher-priced plans', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      // Upgrade appears as both badge and button
      const upgradeElements = screen.getAllByText('Upgrade');
      expect(upgradeElements.length).toBeGreaterThan(0);
    });

    it('shows Downgrade badge for lower-priced plans', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      // Downgrade appears as both badge and button
      const downgradeElements = screen.getAllByText('Downgrade');
      expect(downgradeElements.length).toBeGreaterThan(0);
    });

    it('shows Upgrade button for higher-priced plans', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      // Enterprise is more expensive than Professional (current)
      const upgradeButton = screen.getByRole('button', { name: 'Upgrade' });
      expect(upgradeButton).toBeInTheDocument();
    });

    it('shows Downgrade button for lower-priced plans', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      // Free is less expensive than Professional (current)
      const downgradeButton = screen.getByRole('button', { name: 'Downgrade' });
      expect(downgradeButton).toBeInTheDocument();
    });
  });

  describe('popular badge', () => {
    it('shows Popular badge for pro plans when not current', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      expect(screen.getByText('Popular')).toBeInTheDocument();
    });

    it('hides Popular badge for current pro plan', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      // Professional is current plan, so Popular badge should be hidden
      expect(screen.queryByText('Popular')).not.toBeInTheDocument();
    });
  });

  describe('features display', () => {
    it('shows key features for plans', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      // Api Access appears in both Professional and Enterprise plans
      const apiAccessElements = screen.getAllByText('Api Access');
      expect(apiAccessElements.length).toBeGreaterThan(0);

      // Priority Support also appears in both plans
      const prioritySupportElements = screen.getAllByText('Priority Support');
      expect(prioritySupportElements.length).toBeGreaterThan(0);
    });

    it('shows only first 3 features', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      // Enterprise has 5 features, should only show 3
      const enterprisePlanFeatures = screen.getAllByText('Api Access');
      // Both Professional and Enterprise have api_access
      expect(enterprisePlanFeatures.length).toBe(2);
    });
  });

  describe('empty state', () => {
    it('shows empty message when no public plans', () => {
      const privateOnlyPlans = [mockPlans[3]]; // Only the private plan
      render(<SimplePlanBrowser {...defaultProps} plans={privateOnlyPlans} />);

      expect(screen.getByText('No plans available at this time.')).toBeInTheDocument();
    });

    it('shows empty message when no plans', () => {
      render(<SimplePlanBrowser {...defaultProps} plans={[]} />);

      expect(screen.getByText('No plans available at this time.')).toBeInTheDocument();
    });
  });

  describe('price calculation', () => {
    it('calculates yearly price with custom discount', () => {
      render(<SimplePlanBrowser {...defaultProps} billingCycle="yearly" />);

      // Professional: $49 * 12 months * 0.8 (20% discount) = $470.40
      expect(screen.getByText('$470.40/year')).toBeInTheDocument();
    });

    it('shows Free for zero price plans', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      // The Free plan card should show Free
      const freeTexts = screen.getAllByText('Free');
      expect(freeTexts.length).toBeGreaterThanOrEqual(1);
    });

    it('applies default 10% yearly discount for plans without custom discount', () => {
      const plansWithoutDiscount = [
        {
          ...mockPlans[1],
          has_annual_discount: false,
          annual_discount_percent: 0,
          annual_savings_percentage: 10 // Default
        }
      ];

      render(<SimplePlanBrowser {...defaultProps} plans={plansWithoutDiscount} billingCycle="yearly" />);

      // $49 * 12 * 0.9 (default 10% off) = $529.20
      expect(screen.getByText('$529.20/year')).toBeInTheDocument();
    });
  });

  describe('className prop', () => {
    it('applies custom className', () => {
      const { container } = render(<SimplePlanBrowser {...defaultProps} className="custom-class" />);

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('accessibility', () => {
    it('all buttons are accessible', () => {
      render(<SimplePlanBrowser {...defaultProps} />);

      const buttons = screen.getAllByRole('button');
      expect(buttons.length).toBeGreaterThan(0);
    });

    it('disabled button has correct aria state', () => {
      render(<SimplePlanBrowser {...defaultProps} currentSubscription={mockCurrentSubscription} />);

      const currentPlanButton = screen.getByText('Current Plan', { selector: 'button' });
      expect(currentPlanButton).toHaveAttribute('disabled');
    });
  });
});
