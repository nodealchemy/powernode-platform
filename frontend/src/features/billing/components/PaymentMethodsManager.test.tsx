
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { PaymentMethodsManager } from './PaymentMethodsManager';

// Mock the API and hooks
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification
  })
}));

jest.mock('@/shared/services/paymentMethodsApi', () => ({
  paymentMethodsApi: {
    getPaymentMethods: jest.fn(),
    createSetupIntent: jest.fn(),
    setDefaultPaymentMethod: jest.fn(),
    deletePaymentMethod: jest.fn(),
    getCardBrandIcon: (brand: string) => brand === 'visa' ? '💳' : '💳',
    getPaymentMethodDisplay: (method: any) =>
      method.type === 'card' ? `Visa •••• ${method.card?.last4}` : 'Bank Account',
    formatExpiryDate: (month: number, year: number) => `${month}/${year}`,
    isExpiredCard: () => false
  }
}));

import { paymentMethodsApi } from '@/shared/services/paymentMethodsApi';

describe('PaymentMethodsManager', () => {
  const mockPaymentMethods = [
    {
      id: 'pm_1',
      type: 'card',
      card: {
        brand: 'visa',
        last4: '4242',
        exp_month: 12,
        exp_year: 2025
      }
    },
    {
      id: 'pm_2',
      type: 'card',
      card: {
        brand: 'mastercard',
        last4: '5555',
        exp_month: 6,
        exp_year: 2026
      }
    }
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    (paymentMethodsApi.getPaymentMethods as jest.Mock).mockResolvedValue({
      success: true,
      payment_methods: mockPaymentMethods,
      default_payment_method_id: 'pm_1'
    });
  });

  describe('loading state', () => {
    it('shows loading spinner while loading', () => {
      (paymentMethodsApi.getPaymentMethods as jest.Mock).mockImplementation(
        () => new Promise(resolve => setTimeout(() => resolve({
          success: true,
          payment_methods: [],
          default_payment_method_id: null
        }), 100))
      );

      render(<PaymentMethodsManager />);

      // LoadingSpinner should be visible
      expect(document.querySelector('.flex.items-center.justify-center')).toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows empty state when no payment methods', async () => {
      (paymentMethodsApi.getPaymentMethods as jest.Mock).mockResolvedValue({
        success: true,
        payment_methods: [],
        default_payment_method_id: null
      });

      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('No Payment Methods')).toBeInTheDocument();
      });
      expect(screen.getByText('Add a payment method to enable automatic billing')).toBeInTheDocument();
    });

    it('shows add first payment method button in empty state', async () => {
      (paymentMethodsApi.getPaymentMethods as jest.Mock).mockResolvedValue({
        success: true,
        payment_methods: [],
        default_payment_method_id: null
      });

      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Add Your First Payment Method')).toBeInTheDocument();
      });
    });
  });

  describe('with payment methods', () => {
    it('displays payment methods list', async () => {
      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText(/Visa.*4242/)).toBeInTheDocument();
      });
    });

    it('shows default badge on default method', async () => {
      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Default')).toBeInTheDocument();
      });
    });

    it('shows expiry date for card methods', async () => {
      render(<PaymentMethodsManager />);

      // Wait for payment methods to load
      await waitFor(() => {
        expect(screen.getByText('Default')).toBeInTheDocument();
      });

      // Check that expiry date format is present (12/2025 or Expires 12/2025)
      expect(screen.getByText(/12\/2025/)).toBeInTheDocument();
    });
  });

  describe('header', () => {
    it('displays title', async () => {
      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Payment Methods')).toBeInTheDocument();
      });
    });

    it('displays description', async () => {
      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Manage your payment methods for subscriptions and invoices')).toBeInTheDocument();
      });
    });

    it('shows add button by default', async () => {
      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Add Payment Method')).toBeInTheDocument();
      });
    });

    it('hides add button when showAddButton is false', async () => {
      render(<PaymentMethodsManager showAddButton={false} />);

      await waitFor(() => {
        expect(screen.getByText('Payment Methods')).toBeInTheDocument();
      });
      expect(screen.queryByText('Add Payment Method')).not.toBeInTheDocument();
    });
  });

  describe('actions', () => {
    it('shows Set Default button for non-default methods', async () => {
      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Set Default')).toBeInTheDocument();
      });
    });

    it('calls setDefaultPaymentMethod when Set Default clicked', async () => {
      (paymentMethodsApi.setDefaultPaymentMethod as jest.Mock).mockResolvedValue({
        success: true
      });

      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Set Default')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Set Default'));

      await waitFor(() => {
        expect(paymentMethodsApi.setDefaultPaymentMethod).toHaveBeenCalledWith('pm_2');
      });
    });

    it('calls createSetupIntent when Add Payment Method clicked', async () => {
      (paymentMethodsApi.createSetupIntent as jest.Mock).mockResolvedValue({
        success: true
      });

      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Add Payment Method')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Add Payment Method'));

      await waitFor(() => {
        expect(paymentMethodsApi.createSetupIntent).toHaveBeenCalled();
      });
    });
  });

  describe('delete method', () => {
    it('confirms before deleting', async () => {
      const confirmSpy = jest.spyOn(window, 'confirm').mockReturnValue(false);

      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Default')).toBeInTheDocument();
      });

      // Find delete button (first one for pm_1)
      const deleteButtons = document.querySelectorAll('button.text-theme-error');
      fireEvent.click(deleteButtons[0]);

      expect(confirmSpy).toHaveBeenCalledWith('Are you sure you want to delete this payment method?');
      confirmSpy.mockRestore();
    });

    it('calls deletePaymentMethod on confirmation', async () => {
      jest.spyOn(window, 'confirm').mockReturnValue(true);
      (paymentMethodsApi.deletePaymentMethod as jest.Mock).mockResolvedValue({
        success: true
      });

      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(screen.getByText('Default')).toBeInTheDocument();
      });

      const deleteButtons = document.querySelectorAll('button.text-theme-error');
      fireEvent.click(deleteButtons[0]);

      await waitFor(() => {
        expect(paymentMethodsApi.deletePaymentMethod).toHaveBeenCalledWith('pm_1');
      });
    });
  });

  describe('callbacks', () => {
    it('calls onMethodDeleted after successful delete', async () => {
      jest.spyOn(window, 'confirm').mockReturnValue(true);
      (paymentMethodsApi.deletePaymentMethod as jest.Mock).mockResolvedValue({
        success: true
      });
      const onMethodDeleted = jest.fn();

      render(<PaymentMethodsManager onMethodDeleted={onMethodDeleted} />);

      await waitFor(() => {
        expect(screen.getByText('Default')).toBeInTheDocument();
      });

      const deleteButtons = document.querySelectorAll('button.text-theme-error');
      fireEvent.click(deleteButtons[0]);

      await waitFor(() => {
        expect(onMethodDeleted).toHaveBeenCalledWith('pm_1');
      });
    });
  });

  describe('error handling', () => {
    it('shows notification on API error', async () => {
      (paymentMethodsApi.getPaymentMethods as jest.Mock).mockResolvedValue({
        success: false,
        error: 'Failed to load'
      });

      render(<PaymentMethodsManager />);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to load', 'error');
      });
    });
  });
});
