import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { PlanFormModal } from './PlanFormModal';

// Mock plans API
const mockCreatePlan = jest.fn();
const mockUpdatePlan = jest.fn();
const mockGetDefaultFeatures = jest.fn();
const mockGetDefaultLimits = jest.fn();
const mockGetAvailableCurrencies = jest.fn();
const mockGetAvailableBillingCycles = jest.fn();

jest.mock('@/features/business/plans/services/plansApi', () => ({
  plansApi: {
    createPlan: (...args: any[]) => mockCreatePlan(...args),
    updatePlan: (...args: any[]) => mockUpdatePlan(...args),
    getDefaultFeatures: () => mockGetDefaultFeatures(),
    getDefaultLimits: () => mockGetDefaultLimits(),
    getAvailableCurrencies: () => mockGetAvailableCurrencies(),
    getAvailableBillingCycles: () => mockGetAvailableBillingCycles()
  }
}));

// Mock Modal component
jest.mock('@/shared/components/ui/Modal', () => ({
  Modal: ({ isOpen, title, children, footer }: any) =>
    isOpen ? (
      <div data-testid="modal">
        <h2>{title}</h2>
        <div>{children}</div>
        <div data-testid="modal-footer">{footer}</div>
      </div>
    ) : null
}));

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, loading, variant }: any) => (
    <button
      onClick={onClick}
      disabled={disabled || loading}
      data-loading={loading}
      data-variant={variant}
    >
      {children}
    </button>
  )
}));

// Mock PlanDiscountConfig component
jest.mock('./PlanDiscountConfig', () => ({
  PlanDiscountConfig: ({ onChange }: any) => (
    <div data-testid="discount-config">
      <button onClick={() => onChange('has_annual_discount', true)}>Enable Annual Discount</button>
    </div>
  )
}));

describe('PlanFormModal', () => {
  const defaultProps = {
    isOpen: true,
    onClose: jest.fn(),
    onSaved: jest.fn(),
    showSuccess: jest.fn(),
    showError: jest.fn(),
    plan: null
  };

  const mockPlan = {
    id: 'plan-1',
    name: 'Professional',
    description: 'For growing businesses',
    price_cents: 4900,
    currency: 'USD',
    billing_cycle: 'monthly' as const,
    status: 'active' as const,
    trial_days: 14,
    is_public: true,
    features: { api_access: true },
    limits: { max_users: 10 },
    default_role: 'member',
    metadata: {},
    stripe_price_id: 'price_xxx',
    paypal_plan_id: 'P-xxx',
    has_annual_discount: false,
    annual_discount_percent: 0,
    has_volume_discount: false,
    volume_discount_tiers: [],
    has_promotional_discount: false,
    promotional_discount_percent: 0,
    promotional_discount_start: null,
    promotional_discount_end: null,
    promotional_discount_code: null,
    can_be_deleted: true,
    annual_savings_amount: '$0.00',
    annual_savings_percentage: 0,
    formatted_price: '$49.00',
    monthly_price: '$49.00',
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetDefaultFeatures.mockReturnValue({ api_access: false });
    mockGetDefaultLimits.mockReturnValue({ max_users: 5 });
    mockGetAvailableCurrencies.mockReturnValue([
      { value: 'USD', label: 'USD ($)' },
      { value: 'EUR', label: 'EUR (€)' }
    ]);
    mockGetAvailableBillingCycles.mockReturnValue([
      { value: 'monthly', label: 'Monthly' },
      { value: 'yearly', label: 'Yearly' }
    ]);
    mockCreatePlan.mockResolvedValue({ success: true });
    mockUpdatePlan.mockResolvedValue({ success: true });
  });

  describe('rendering', () => {
    it('renders modal when open', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByTestId('modal')).toBeInTheDocument();
    });

    it('does not render when closed', () => {
      render(<PlanFormModal {...defaultProps} isOpen={false} />);

      expect(screen.queryByTestId('modal')).not.toBeInTheDocument();
    });

    it('shows Create New Plan title for new plan', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Create New Plan')).toBeInTheDocument();
    });

    it('shows Edit Plan title when editing', () => {
      render(<PlanFormModal {...defaultProps} plan={mockPlan} />);

      expect(screen.getByText('Edit Plan')).toBeInTheDocument();
    });
  });

  describe('tabs', () => {
    it('shows Basic Info tab', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Basic Info')).toBeInTheDocument();
    });

    it('shows Features & Limits tab', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Features & Limits')).toBeInTheDocument();
    });

    it('shows Discounts tab', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Discounts')).toBeInTheDocument();
    });

    it('starts on Basic Info tab', () => {
      render(<PlanFormModal {...defaultProps} />);

      // Basic tab should be active - check for form fields
      expect(screen.getByText('Plan Information')).toBeInTheDocument();
    });

    it('switches to Features tab when clicked', () => {
      render(<PlanFormModal {...defaultProps} />);

      fireEvent.click(screen.getByText('Features & Limits'));

      expect(screen.getByText('Features & Limits Configuration')).toBeInTheDocument();
    });

    it('switches to Discounts tab when clicked', () => {
      render(<PlanFormModal {...defaultProps} />);

      fireEvent.click(screen.getByText('Discounts'));

      expect(screen.getByTestId('discount-config')).toBeInTheDocument();
    });
  });

  describe('basic info tab', () => {
    it('shows plan name field', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Plan Name *')).toBeInTheDocument();
    });

    it('shows description field', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Description')).toBeInTheDocument();
    });

    it('shows price field', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Price (cents) *')).toBeInTheDocument();
    });

    it('shows currency field', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Currency')).toBeInTheDocument();
    });

    it('shows billing cycle field', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Billing Cycle')).toBeInTheDocument();
    });

    it('shows status field', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Status')).toBeInTheDocument();
    });

    it('shows trial days field', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Trial Days')).toBeInTheDocument();
    });

    it('shows public plan checkbox', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Public plan (visible to new customers)')).toBeInTheDocument();
    });
  });

  describe('form population for editing', () => {
    it('populates name when editing', () => {
      render(<PlanFormModal {...defaultProps} plan={mockPlan} />);

      const nameInput = screen.getByPlaceholderText('e.g. Professional Plan') as HTMLInputElement;
      expect(nameInput.value).toBe('Professional');
    });

    it('populates description when editing', () => {
      render(<PlanFormModal {...defaultProps} plan={mockPlan} />);

      const descInput = screen.getByPlaceholderText('Describe what this plan includes...') as HTMLTextAreaElement;
      expect(descInput.value).toBe('For growing businesses');
    });

    it('populates price when editing', () => {
      render(<PlanFormModal {...defaultProps} plan={mockPlan} />);

      const priceInput = screen.getByPlaceholderText('2999') as HTMLInputElement;
      expect(priceInput.value).toBe('4900');
    });
  });

  describe('form input', () => {
    it('updates name field value', () => {
      render(<PlanFormModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('e.g. Professional Plan') as HTMLInputElement;
      fireEvent.change(nameInput, { target: { value: 'Enterprise' } });

      expect(nameInput.value).toBe('Enterprise');
    });

    it('updates price field value', () => {
      render(<PlanFormModal {...defaultProps} />);

      const priceInput = screen.getByPlaceholderText('2999') as HTMLInputElement;
      fireEvent.change(priceInput, { target: { value: '9900' } });

      expect(priceInput.value).toBe('9900');
    });
  });

  describe('form submission - create', () => {
    it('calls createPlan on submit for new plan', async () => {
      render(<PlanFormModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('e.g. Professional Plan');
      fireEvent.change(nameInput, { target: { value: 'New Plan' } });

      const submitButton = screen.getByText('Create Plan');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockCreatePlan).toHaveBeenCalled();
      });
    });

    it('shows success notification on create', async () => {
      const showSuccess = jest.fn();
      render(<PlanFormModal {...defaultProps} showSuccess={showSuccess} />);

      const nameInput = screen.getByPlaceholderText('e.g. Professional Plan');
      fireEvent.change(nameInput, { target: { value: 'New Plan' } });

      fireEvent.click(screen.getByText('Create Plan'));

      await waitFor(() => {
        expect(showSuccess).toHaveBeenCalledWith('Plan created successfully');
      });
    });

    it('calls onSaved after successful create', async () => {
      const onSaved = jest.fn();
      render(<PlanFormModal {...defaultProps} onSaved={onSaved} />);

      const nameInput = screen.getByPlaceholderText('e.g. Professional Plan');
      fireEvent.change(nameInput, { target: { value: 'New Plan' } });

      fireEvent.click(screen.getByText('Create Plan'));

      await waitFor(() => {
        expect(onSaved).toHaveBeenCalled();
      });
    });

    it('calls onClose after successful create', async () => {
      const onClose = jest.fn();
      render(<PlanFormModal {...defaultProps} onClose={onClose} />);

      const nameInput = screen.getByPlaceholderText('e.g. Professional Plan');
      fireEvent.change(nameInput, { target: { value: 'New Plan' } });

      fireEvent.click(screen.getByText('Create Plan'));

      await waitFor(() => {
        expect(onClose).toHaveBeenCalled();
      });
    });
  });

  describe('form submission - update', () => {
    it('calls updatePlan on submit for existing plan', async () => {
      render(<PlanFormModal {...defaultProps} plan={mockPlan} />);

      const nameInput = screen.getByPlaceholderText('e.g. Professional Plan');
      fireEvent.change(nameInput, { target: { value: 'Updated Plan' } });

      fireEvent.click(screen.getByText('Update Plan'));

      await waitFor(() => {
        expect(mockUpdatePlan).toHaveBeenCalledWith('plan-1', expect.any(Object));
      });
    });

    it('shows success notification on update', async () => {
      const showSuccess = jest.fn();
      render(<PlanFormModal {...defaultProps} plan={mockPlan} showSuccess={showSuccess} />);

      fireEvent.click(screen.getByText('Update Plan'));

      await waitFor(() => {
        expect(showSuccess).toHaveBeenCalledWith('Plan updated successfully');
      });
    });
  });

  describe('error handling', () => {
    it('shows error notification on create failure', async () => {
      mockCreatePlan.mockRejectedValue(new Error('Create failed'));
      const showError = jest.fn();

      render(<PlanFormModal {...defaultProps} showError={showError} />);

      const nameInput = screen.getByPlaceholderText('e.g. Professional Plan');
      fireEvent.change(nameInput, { target: { value: 'New Plan' } });

      fireEvent.click(screen.getByText('Create Plan'));

      await waitFor(() => {
        expect(showError).toHaveBeenCalledWith('Create failed');
      });
    });

    it('shows error notification on update failure', async () => {
      mockUpdatePlan.mockRejectedValue(new Error('Update failed'));
      const showError = jest.fn();

      render(<PlanFormModal {...defaultProps} plan={mockPlan} showError={showError} />);

      fireEvent.click(screen.getByText('Update Plan'));

      await waitFor(() => {
        expect(showError).toHaveBeenCalledWith('Update failed');
      });
    });
  });

  describe('cancel button', () => {
    it('shows Cancel button', () => {
      render(<PlanFormModal {...defaultProps} />);

      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('calls onClose when Cancel clicked', () => {
      const onClose = jest.fn();
      render(<PlanFormModal {...defaultProps} onClose={onClose} />);

      fireEvent.click(screen.getByText('Cancel'));

      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('loading state', () => {
    it('shows Creating... text when submitting new plan', async () => {
      mockCreatePlan.mockImplementation(() => new Promise(() => {}));

      render(<PlanFormModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('e.g. Professional Plan');
      fireEvent.change(nameInput, { target: { value: 'New Plan' } });

      fireEvent.click(screen.getByText('Create Plan'));

      await waitFor(() => {
        expect(screen.getByText('Creating...')).toBeInTheDocument();
      });
    });

    it('shows Updating... text when submitting existing plan', async () => {
      mockUpdatePlan.mockImplementation(() => new Promise(() => {}));

      render(<PlanFormModal {...defaultProps} plan={mockPlan} />);

      fireEvent.click(screen.getByText('Update Plan'));

      await waitFor(() => {
        expect(screen.getByText('Updating...')).toBeInTheDocument();
      });
    });
  });

  describe('keyboard navigation', () => {
    it('allows Enter key to select tab', () => {
      render(<PlanFormModal {...defaultProps} />);

      const featuresTab = screen.getByText('Features & Limits');
      fireEvent.keyDown(featuresTab, { key: 'Enter' });

      expect(screen.getByText('Features & Limits Configuration')).toBeInTheDocument();
    });

    it('allows Space key to select tab', () => {
      render(<PlanFormModal {...defaultProps} />);

      const featuresTab = screen.getByText('Features & Limits');
      fireEvent.keyDown(featuresTab, { key: ' ' });

      expect(screen.getByText('Features & Limits Configuration')).toBeInTheDocument();
    });

    it('allows ArrowRight key to navigate tabs', () => {
      render(<PlanFormModal {...defaultProps} />);

      const basicTab = screen.getByText('Basic Info');
      fireEvent.keyDown(basicTab, { key: 'ArrowRight' });

      // Should move to Features tab
      expect(screen.getByText('Features & Limits Configuration')).toBeInTheDocument();
    });

    it('allows ArrowLeft key to navigate tabs', () => {
      render(<PlanFormModal {...defaultProps} />);

      // First go to Features
      fireEvent.click(screen.getByText('Features & Limits'));

      const featuresTab = screen.getByText('Features & Limits');
      fireEvent.keyDown(featuresTab, { key: 'ArrowLeft' });

      // Should move back to Basic tab
      expect(screen.getByText('Plan Information')).toBeInTheDocument();
    });
  });
});
