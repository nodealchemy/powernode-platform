import { billingApi } from './billingApi';
import { api } from '@/shared/services/api';
import { createMockAxiosResponse } from '../../../test-utils';

// Mock the API client
jest.mock('@/shared/services/api', () => ({
  api: {
    get: jest.fn(),
    post: jest.fn(),
    put: jest.fn(),
    delete: jest.fn()
  }
}));

const mockApi = api as jest.Mocked<typeof api>;

describe('billingApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('getInvoices', () => {
    it('should fetch invoices successfully', async () => {
      const mockInvoices = [
        {
          id: 'inv_123',
          invoice_number: 'INV-001',
          total_amount: '29.99',
          currency: 'USD',
          status: 'paid',
          created_at: '2023-01-01T00:00:00Z',
          due_date: '2023-01-15T00:00:00Z',
          subtotal: '29.99'
        }
      ];

      mockApi.get.mockResolvedValue(createMockAxiosResponse({
        invoices: mockInvoices,
        pagination: {
          current_page: 1,
          per_page: 20,
          total_count: 1,
          total_pages: 1
        }
      }));

      const result = await billingApi.getInvoices();

      expect(mockApi.get).toHaveBeenCalledWith('/billing/invoices', {
        params: { page: 1, per_page: 20 }
      });
      expect(result.data).toEqual(mockInvoices);
    });

    it('should handle pagination parameters', async () => {
      mockApi.get.mockResolvedValue(createMockAxiosResponse({
        invoices: [],
        pagination: {
          current_page: 2,
          per_page: 10,
          total_count: 0,
          total_pages: 0
        }
      }));

      await billingApi.getInvoices(2, 10);

      expect(mockApi.get).toHaveBeenCalledWith('/billing/invoices', {
        params: { page: 2, per_page: 10 }
      });
    });
  });

  describe('createInvoice', () => {
    it('should create invoice successfully', async () => {
      const invoiceData = {
        currency: 'USD',
        due_date: '2023-12-31',
        notes: 'Monthly subscription',
        line_items: [
          {
            description: 'Premium Plan',
            quantity: 1,
            unit_price: 2999
          }
        ]
      };

      const mockResponse = {
        success: true,
        invoice: {
          id: 'inv_456',
          invoice_number: 'INV-002',
          total_amount: '29.99',
          status: 'draft'
        }
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await billingApi.createInvoice(invoiceData);

      expect(mockApi.post).toHaveBeenCalledWith('/billing/invoices', {
        invoice: {
          currency: invoiceData.currency,
          due_date: invoiceData.due_date,
          notes: invoiceData.notes
        },
        line_items: invoiceData.line_items
      });
      expect(result).toEqual(mockResponse);
    });
  });

  describe('createPaymentIntent', () => {
    it('should create payment intent successfully', async () => {
      const paymentData = {
        amount_cents: 2999,
        currency: 'USD',
        description: 'One-time payment'
      };

      const mockResponse = {
        success: true,
        client_secret: 'pi_secret_123',
        payment_intent_id: 'pi_456'
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await billingApi.createPaymentIntent(paymentData);

      expect(mockApi.post).toHaveBeenCalledWith('/billing/payment-intent', paymentData);
      expect(result).toEqual(mockResponse);
    });

    it('should handle payment intent failure', async () => {
      const paymentData = {
        amount_cents: 2999,
        currency: 'USD',
        description: 'One-time payment'
      };

      mockApi.post.mockRejectedValue({
        response: {
          data: {
            success: false,
            error: 'Payment failed: insufficient funds'
          }
        }
      });

      // Now returns error response instead of throwing
      const result = await billingApi.createPaymentIntent(paymentData);
      expect(result.success).toBe(false);
      expect(result.error).toBe('Payment failed: insufficient funds');
    });
  });

  describe('getPaymentMethods', () => {
    it('should fetch payment methods successfully', async () => {
      const mockPaymentMethods = [
        {
          id: 'pm_123',
          type: 'card',
          last4: '4242',
          brand: 'visa',
          is_default: true
        }
      ];

      mockApi.get.mockResolvedValue(createMockAxiosResponse({
        payment_methods: mockPaymentMethods
      }));

      const result = await billingApi.getPaymentMethods();

      expect(mockApi.get).toHaveBeenCalledWith('/billing/payment-methods');
      expect(result.data).toEqual(mockPaymentMethods);
    });
  });

  describe('addPaymentMethod', () => {
    it('should add payment method successfully', async () => {
      const paymentMethodData = {
        type: 'card',
        token: 'tok_123',
        is_default: false
      };

      const mockResponseData = {
        id: 'pm_456',
        ...paymentMethodData
      };

      const mockResponse = {
        success: true,
        data: mockResponseData
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponseData));

      const result = await billingApi.addPaymentMethod(paymentMethodData);

      expect(mockApi.post).toHaveBeenCalledWith('/billing/payment-methods', paymentMethodData);
      expect(result).toEqual(mockResponse);
    });
  });

  describe('removePaymentMethod', () => {
    it('should remove payment method successfully', async () => {
      const paymentMethodId = 'pm_123';

      mockApi.delete.mockResolvedValue(createMockAxiosResponse({
        success: true,
        message: 'Payment method removed'
      }));

      const result = await billingApi.removePaymentMethod(paymentMethodId);

      expect(mockApi.delete).toHaveBeenCalledWith(`/billing/payment-methods/${paymentMethodId}`);
      expect(result.success).toBe(true);
    });
  });

  describe('setDefaultPaymentMethod', () => {
    it('should set default payment method successfully', async () => {
      const paymentMethodId = 'pm_123';

      mockApi.put.mockResolvedValue(createMockAxiosResponse({
        success: true,
        data: {
          id: 'pm_123',
          is_default: true
        }
      }));

      const result = await billingApi.setDefaultPaymentMethod(paymentMethodId);

      expect(mockApi.put).toHaveBeenCalledWith(`/billing/payment-methods/${paymentMethodId}/default`);
      expect(result.success).toBe(true);
    });
  });

  describe('getSubscriptionBilling', () => {
    it('should fetch subscription billing successfully', async () => {
      const mockSubscriptionBilling = {
        subscription: {
          id: 'sub_123',
          plan: {
            id: 'plan_pro',
            name: 'Pro Plan',
            price: '29.99',
            billing_cycle: 'monthly'
          },
          status: 'active',
          current_period_start: '2024-01-01T00:00:00Z',
          current_period_end: '2024-02-01T00:00:00Z'
        },
        billing_history: []
      };

      mockApi.get.mockResolvedValue(createMockAxiosResponse(mockSubscriptionBilling));

      const result = await billingApi.getSubscriptionBilling();

      expect(mockApi.get).toHaveBeenCalledWith('/billing/subscription');
      expect(result).toEqual(mockSubscriptionBilling);
    });
  });

  describe('getBillingHistory', () => {
    it('should fetch billing history successfully', async () => {
      const mockHistory = [
        {
          id: 'hist_123',
          type: 'payment',
          amount_cents: 2999,
          status: 'succeeded',
          created_at: '2023-01-01T00:00:00Z'
        }
      ];

      mockApi.get.mockResolvedValue(createMockAxiosResponse({
        success: true,
        data: mockHistory
      }));

      const result = await billingApi.getBillingHistory();

      expect(mockApi.get).toHaveBeenCalledWith('/billing/history');
      expect(result.data).toEqual(mockHistory);
    });

    it('should handle date range filters', async () => {
      const filters = {
        start_date: '2023-01-01',
        end_date: '2023-01-31'
      };

      mockApi.get.mockResolvedValue(createMockAxiosResponse({
        success: true,
        data: []
      }));

      await billingApi.getBillingHistory(filters);

      expect(mockApi.get).toHaveBeenCalledWith('/billing/history', {
        params: filters
      });
    });
  });

  describe('error handling', () => {
    it('should handle network errors', async () => {
      mockApi.get.mockRejectedValue(new Error('Network Error'));

      // getInvoices now catches errors and throws error response object
      await expect(billingApi.getInvoices()).rejects.toMatchObject({
        success: false,
        error: 'Network Error'
      });
    });

    it('should handle API errors with error messages', async () => {
      mockApi.post.mockRejectedValue({
        response: {
          data: {
            success: false,
            error: 'Invalid payment method'
          }
        }
      });

      // processPayment now catches errors and returns error response
      const result = await billingApi.processPayment({
        invoice_id: 'inv_123',
        payment_method_id: 'invalid',
        amount_cents: 1000
      });

      expect(result.success).toBe(false);
      expect(result.error).toBe('Invalid payment method');
    });
  });
});