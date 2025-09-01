import React from 'react';
import { screen, fireEvent, waitFor } from '@testing-library/react';
import { renderWithProviders, mockAuthenticatedState } from '@/shared/utils/test-utils';
import { PlanCard } from './PlanCard';

// Mock theme context
jest.mock('@/shared/hooks/ThemeContext', () => ({
  useTheme: () => ({ 
    theme: 'light',
    toggleTheme: jest.fn() 
  })
}));

const mockPlan = {
  id: '1',
  name: 'Pro Plan',
  description: 'Perfect for growing businesses',
  price_cents: 2999, // $29.99
  currency: 'USD',
  billing_cycle: 'monthly',
  trial_days: 14,
  has_annual_discount: true,
  annual_discount_percent: 20,
  features: {
    max_users: 100,
    storage_gb: 100,
    api_access: true,
    advanced_analytics: true,
    priority_support: true,
    custom_integrations: true
  }
};

describe('PlanCard', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders plan information correctly', () => {
    renderWithProviders(<PlanCard plan={mockPlan} />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.getByText('Pro Plan')).toBeInTheDocument();
    expect(screen.getByText('Perfect for growing businesses')).toBeInTheDocument();
    expect(screen.getByText('$29')).toBeInTheDocument(); // Component shows integer price
    expect(screen.getByText('/month')).toBeInTheDocument(); // Component shows "/month"
    // Trial days display would depend on component implementation
  });

  it('displays popular badge for featured plans', () => {
    renderWithProviders(<PlanCard plan={mockPlan} featured={true} />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.getByText('Most Popular')).toBeInTheDocument();
  });

  it('does not display popular badge for non-featured plans', () => {
    renderWithProviders(<PlanCard plan={mockPlan} featured={false} />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.queryByText('Most Popular')).not.toBeInTheDocument();
  });

  it('renders all plan features', () => {
    renderWithProviders(<PlanCard plan={mockPlan} />, {
      preloadedState: mockAuthenticatedState
    });
    
    // Component converts feature keys to display labels
    expect(screen.getByText('API Access')).toBeInTheDocument();
    expect(screen.getByText('Advanced Analytics')).toBeInTheDocument();
    expect(screen.getByText('Priority Support')).toBeInTheDocument();
    expect(screen.getByText('Custom Integrations')).toBeInTheDocument();
  });

  it('displays correct pricing for yearly plans', () => {
    const yearlyPlan = {
      ...mockPlan,
      billing_cycle: 'yearly',
      price_cents: 299900 // $2999.00 per year
    };
    
    renderWithProviders(<PlanCard plan={yearlyPlan} />, {
      preloadedState: mockAuthenticatedState
    });
    
    // Component converts yearly to monthly: $2999/year ÷ 12 = $249.91 → Math.floor = $249
    expect(screen.getByText('$249')).toBeInTheDocument();
    expect(screen.getByText('/month')).toBeInTheDocument(); // Component shows monthly price
  });

  it('displays correct pricing for quarterly plans', () => {
    const quarterlyPlan = {
      ...mockPlan,
      billing_cycle: 'quarterly',
      price_cents: 7999 // $79.99 per quarter
    };
    
    renderWithProviders(<PlanCard plan={quarterlyPlan} />, {
      preloadedState: mockAuthenticatedState
    });
    
    // Component converts quarterly to monthly: $79.99/quarter ÷ 3 = $26.66 → Math.floor = $26
    expect(screen.getByText('$26')).toBeInTheDocument();
    expect(screen.getByText('/month')).toBeInTheDocument(); // Component shows monthly price
  });

  it('handles free plans correctly', () => {
    const freePlan = {
      ...mockPlan,
      name: 'Free Plan',
      price_cents: 0
    };
    
    renderWithProviders(<PlanCard plan={freePlan} />, {
      preloadedState: mockAuthenticatedState
    });
    
    // Component shows 'Free' in both price section and badge - use getAllByText
    expect(screen.getAllByText('Free')).toHaveLength(2); // Badge and price display
    // Component doesn't show /month for free plans, but shows /month suffix differently
    expect(screen.queryByText('/month')).not.toBeInTheDocument();
  });

  it('calls onSelect when select button is clicked', () => {
    const mockOnSelect = jest.fn();
    renderWithProviders(<PlanCard plan={mockPlan} onSelect={mockOnSelect} />, {
      preloadedState: mockAuthenticatedState
    });
    
    const selectButton = screen.getByRole('button', { name: /select plan/i });
    fireEvent.click(selectButton);
    
    expect(mockOnSelect).toHaveBeenCalledWith(mockPlan);
  });

  it('shows current plan indicator', () => {
    renderWithProviders(<PlanCard plan={mockPlan} isCurrentPlan={true} />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.getByText('Current Plan')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /select plan/i })).not.toBeInTheDocument();
  });

  it('disables selection when disabled', () => {
    const mockOnSelect = jest.fn();
    renderWithProviders(<PlanCard plan={mockPlan} onSelect={mockOnSelect} disabled={true} />, {
      preloadedState: mockAuthenticatedState
    });
    
    const selectButton = screen.getByRole('button', { name: /select plan/i });
    expect(selectButton).toBeDisabled();
    
    fireEvent.click(selectButton);
    expect(mockOnSelect).not.toHaveBeenCalled();
  });

  it('shows loading state during selection', () => {
    renderWithProviders(<PlanCard plan={mockPlan} loading={true} />, {
      preloadedState: mockAuthenticatedState
    });
    
    // Use more specific selection since there might be multiple buttons (billing toggle)
    const selectButton = screen.getByRole('button', { name: /selecting/i });
    expect(selectButton).toBeDisabled();
    expect(screen.getByText(/selecting/i)).toBeInTheDocument();
  });

  it('applies correct theme styling', () => {
    const { container } = renderWithProviders(<PlanCard plan={mockPlan} />, {
      preloadedState: mockAuthenticatedState
    });
    
    // Should have theme-aware classes
    const cardContainer = container.querySelector('[class*="bg-theme"]');
    expect(cardContainer).toBeInTheDocument();
  });

  it('highlights popular plan with special styling', () => {
    const { container } = renderWithProviders(<PlanCard plan={mockPlan} featured={true} />, {
      preloadedState: mockAuthenticatedState
    });
    
    // Featured plans should have border-primary class
    const popularCard = container.querySelector('[class*="border-primary"]');
    expect(popularCard).toBeInTheDocument();
  });

  it('formats large prices correctly', () => {
    const enterprisePlan = {
      ...mockPlan,
      price_cents: 9999900 // $99,999.00
    };
    
    renderWithProviders(<PlanCard plan={enterprisePlan} />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.getByText('$99999')).toBeInTheDocument();
  });

  it('handles missing features gracefully', () => {
    const planWithoutFeatures = {
      ...mockPlan,
      features: []
    };
    
    renderWithProviders(<PlanCard plan={planWithoutFeatures} />, {
      preloadedState: mockAuthenticatedState
    });
    
    // Should still render the plan card without errors
    expect(screen.getByText('Pro Plan')).toBeInTheDocument();
  });

  it('shows trial information when available', () => {
    renderWithProviders(<PlanCard plan={mockPlan} />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.getByText('14-day free trial')).toBeInTheDocument();
  });

  it('hides trial information when not available', () => {
    const planWithoutTrial = {
      ...mockPlan,
      trial_days: 0
    };
    
    renderWithProviders(<PlanCard plan={planWithoutTrial} />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.queryByText(/free trial/i)).not.toBeInTheDocument();
  });

  it('supports custom action buttons', () => {
    const customAction = (
      <button data-testid="custom-action">Custom Action</button>
    );
    
    renderWithProviders(<PlanCard plan={mockPlan} customAction={customAction} />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.getByTestId('custom-action')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /select plan/i })).not.toBeInTheDocument();
  });

  it('shows upgrade/downgrade context', () => {
    renderWithProviders(<PlanCard plan={mockPlan} upgradeContext="upgrade" />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.getByText(/upgrade/i)).toBeInTheDocument();
  });

  it('handles different currencies', () => {
    const euroPlan = {
      ...mockPlan,
      currency: 'EUR',
      price_cents: 2599
    };
    
    renderWithProviders(<PlanCard plan={euroPlan} />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.getByText('€25.99')).toBeInTheDocument();
  });
});