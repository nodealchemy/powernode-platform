import { billingApi } from '../billingApi';
import { api } from '@/shared/services/api';
import { getErrorMessage } from '@/shared/utils/errorHandling';
import { createMockAxiosResponse } from '../../../../test-utils/mockAxios';

// Mock the api module
jest.mock('@/shared/services/api', () => ({
  api: {
    get: jest.fn(),
    post: jest.fn(),
    put: jest.fn(),
    delete: jest.fn(),
  },
}));

// Mock the error handling utility
jest.mock('@/shared/utils/errorHandling', () => ({
  ...jest.requireActual('@/shared/utils/errorHandling'),
  getErrorMessage: jest.fn(),
}));

const mockApi = api as jest.Mocked<typeof api>;
const mockGetErrorMessage = getErrorMessage as jest.MockedFunction<typeof getErrorMessage>;

describe('billingApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Default mock implementation that returns the error message from response
    mockGetErrorMessage.mockImplementation((error: unknown) => {
      if (error instanceof Error) {
        return error.message;
      }
      if (typeof error === 'object' && error !== null) {
        const err = error as { response?: { data?: { error?: string; message?: string } } };
        return err.response?.data?.error || err.response?.data?.message || 'Unknown error';
      }
      return 'Unknown error';
    });
  });

  describe('getOverview', () => {
    it('returns billing overview on success', async () => {
      const mockData = {
        outstanding: 100,
        this_month: 500,
        collected: 400,
        success_rate: 0.95,
      };

      mockApi.get.mockResolvedValue(createMockAxiosResponse(mockData));

      const result = await billingApi.getOverview();

      expect(mockApi.get).toHaveBeenCalledWith('/billing');
      expect(result).toEqual(mockData);
    });

    it('throws error with message on failure', async () => {
      const error = {
        response: { data: { error: 'Failed to fetch billing overview' } },
      };

      mockApi.get.mockRejectedValue(error);

      await expect(billingApi.getOverview()).rejects.toEqual({
        success: false,
        error: 'Failed to fetch billing overview',
      });
    });

    it('handles network errors', async () => {
      const networkError = new TypeError('Network request failed');
      mockApi.get.mockRejectedValue(networkError);

      await expect(billingApi.getOverview()).rejects.toEqual({
        success: false,
        error: 'Network request failed',
      });
    });
  });

  describe('getSubscriptionBilling', () => {
    it('returns subscription billing data on success', async () => {
      const mockData = {
        subscription: {
          id: 'sub_123',
          plan: { name: 'Pro', price: '99.00' },
          status: 'active',
        },
      };

      mockApi.get.mockResolvedValue(createMockAxiosResponse(mockData));

      const result = await billingApi.getSubscriptionBilling();

      expect(mockApi.get).toHaveBeenCalledWith('/billing/subscription');
      expect(result).toEqual(mockData);
    });

    it('throws error on failure', async () => {
      const error = {
        response: { data: { error: 'Subscription not found' } },
      };

      mockApi.get.mockRejectedValue(error);

      await expect(billingApi.getSubscriptionBilling()).rejects.toEqual({
        success: false,
        error: 'Subscription not found',
      });
    });
  });

  describe('getInvoices', () => {
    it('returns paginated invoices on success', async () => {
      const mockResponse = {
        invoices: [
          { id: 'inv_1', invoice_number: 'INV-001', total_amount: '100.00' },
          { id: 'inv_2', invoice_number: 'INV-002', total_amount: '200.00' },
        ],
        pagination: {
          current_page: 1,
          per_page: 20,
          total_count: 2,
          total_pages: 1,
        },
      };

      mockApi.get.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await billingApi.getInvoices(1, 20);

      expect(mockApi.get).toHaveBeenCalledWith('/billing/invoices', {
        params: { page: 1, per_page: 20 },
      });
      expect(result.data).toEqual(mockResponse.invoices);
      expect(result.pagination).toEqual(mockResponse.pagination);
    });

    it('throws error on failure', async () => {
      mockApi.get.mockRejectedValue({
        response: { data: { error: 'Failed to fetch invoices' } },
      });

      await expect(billingApi.getInvoices()).rejects.toEqual({
        success: false,
        error: 'Failed to fetch invoices',
      });
    });
  });

  describe('createInvoice', () => {
    it('creates invoice and returns success response', async () => {
      const invoiceData = {
        currency: 'USD',
        due_date: '2024-02-01',
        line_items: [{ description: 'Service', quantity: 1, unit_price: 100 }],
      };

      const mockResponse = {
        success: true,
        invoice: {
          id: 'inv_new',
          invoice_number: 'INV-003',
          total_amount: '100.00',
          status: 'draft',
        },
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await billingApi.createInvoice(invoiceData);

      expect(mockApi.post).toHaveBeenCalledWith('/billing/invoices', {
        invoice: {
          currency: 'USD',
          due_date: '2024-02-01',
          notes: undefined,
        },
        line_items: invoiceData.line_items,
      });
      expect(result).toEqual(mockResponse);
    });

    it('returns error response on failure', async () => {
      mockApi.post.mockRejectedValue({
        response: { data: { error: 'Invalid invoice data' } },
      });

      const result = await billingApi.createInvoice({
        currency: 'USD',
        due_date: '2024-02-01',
        line_items: [],
      });

      expect(result.success).toBe(false);
      expect(result.error).toBe('Invalid invoice data');
    });
  });

  describe('getPaymentMethods', () => {
    it('returns payment methods on success', async () => {
      const mockMethods = [
        { id: 'pm_1', card_brand: 'visa', card_last_four: '4242' },
        { id: 'pm_2', card_brand: 'mastercard', card_last_four: '5555' },
      ];

      mockApi.get.mockResolvedValue(createMockAxiosResponse({ payment_methods: mockMethods }));

      const result = await billingApi.getPaymentMethods();

      expect(mockApi.get).toHaveBeenCalledWith('/billing/payment-methods');
      expect(result.data).toEqual(mockMethods);
    });

    it('returns empty array with error on failure', async () => {
      mockApi.get.mockRejectedValue({
        response: { data: { error: 'Failed to fetch payment methods' } },
      });

      const result = await billingApi.getPaymentMethods();

      expect(result.data).toEqual([]);
      expect(result.error).toBe('Failed to fetch payment methods');
    });
  });

  describe('createPaymentMethod', () => {
    it('creates payment method on success', async () => {
      const mockResponse = {
        success: true,
        payment_method: {
          id: 'pm_new',
          card_brand: 'visa',
          card_last_four: '1234',
        },
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await billingApi.createPaymentMethod('pm_stripe_123', 'stripe');

      expect(mockApi.post).toHaveBeenCalledWith('/billing/payment-methods', {
        payment_method_id: 'pm_stripe_123',
        provider: 'stripe',
      });
      expect(result).toEqual(mockResponse);
    });

    it('returns error on failure', async () => {
      mockApi.post.mockRejectedValue({
        response: { data: { error: 'Invalid payment method' } },
      });

      const result = await billingApi.createPaymentMethod('invalid', 'stripe');

      expect(result.success).toBe(false);
      expect(result.error).toBe('Invalid payment method');
    });
  });

  describe('createPaymentIntent', () => {
    it('creates payment intent on success', async () => {
      const mockResponse = {
        success: true,
        client_secret: 'pi_secret_123',
        payment_intent_id: 'pi_123',
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await billingApi.createPaymentIntent({
        amount_cents: 1000,
        currency: 'USD',
      });

      expect(mockApi.post).toHaveBeenCalledWith('/billing/payment-intent', {
        amount_cents: 1000,
        currency: 'USD',
      });
      expect(result).toEqual(mockResponse);
    });

    it('returns error on failure', async () => {
      mockApi.post.mockRejectedValue({
        response: { data: { error: 'Payment intent creation failed' } },
      });

      const result = await billingApi.createPaymentIntent({ amount_cents: 1000 });

      expect(result.success).toBe(false);
      expect(result.error).toBe('Payment intent creation failed');
    });
  });

  describe('removePaymentMethod', () => {
    it('removes payment method on success', async () => {
      mockApi.delete.mockResolvedValue(createMockAxiosResponse({ success: true }));

      const result = await billingApi.removePaymentMethod('pm_123');

      expect(mockApi.delete).toHaveBeenCalledWith('/billing/payment-methods/pm_123');
      expect(result.success).toBe(true);
    });

    it('returns error on failure', async () => {
      mockApi.delete.mockRejectedValue({
        response: { data: { error: 'Cannot remove default payment method' } },
      });

      const result = await billingApi.removePaymentMethod('pm_123');

      expect(result.success).toBe(false);
      expect(result.error).toBe('Cannot remove default payment method');
    });
  });

  describe('setDefaultPaymentMethod', () => {
    it('sets default payment method on success', async () => {
      mockApi.put.mockResolvedValue(createMockAxiosResponse({ success: true }));

      const result = await billingApi.setDefaultPaymentMethod('pm_123');

      expect(mockApi.put).toHaveBeenCalledWith('/billing/payment-methods/pm_123/default');
      expect(result.success).toBe(true);
    });

    it('returns error on failure', async () => {
      mockApi.put.mockRejectedValue({
        response: { data: { error: 'Payment method not found' } },
      });

      const result = await billingApi.setDefaultPaymentMethod('pm_invalid');

      expect(result.success).toBe(false);
      expect(result.error).toBe('Payment method not found');
    });
  });

  describe('getBillingHistory', () => {
    it('returns billing history without filters', async () => {
      const mockHistory = [
        { id: 'inv_1', invoice_number: 'INV-001', amount: '100.00', status: 'paid' },
      ];

      mockApi.get.mockResolvedValue(createMockAxiosResponse({ data: mockHistory }));

      const result = await billingApi.getBillingHistory();

      expect(mockApi.get).toHaveBeenCalledWith('/billing/history');
      expect(result.data).toEqual(mockHistory);
    });

    it('returns billing history with filters', async () => {
      const filters = {
        start_date: '2024-01-01',
        end_date: '2024-01-31',
        page: 1,
        per_page: 10,
      };

      mockApi.get.mockResolvedValue(createMockAxiosResponse({
        data: [],
        pagination: { current_page: 1, per_page: 10, total_count: 0, total_pages: 0 },
      }));

      const result = await billingApi.getBillingHistory(filters);

      expect(mockApi.get).toHaveBeenCalledWith('/billing/history', { params: filters });
      expect(result.pagination).toBeDefined();
    });

    it('returns empty array with error on failure', async () => {
      mockApi.get.mockRejectedValue({
        response: { data: { error: 'Failed to fetch history' } },
      });

      const result = await billingApi.getBillingHistory();

      expect(result.data).toEqual([]);
      expect(result.error).toBe('Failed to fetch history');
    });
  });

  describe('processPayment', () => {
    it('processes payment on success', async () => {
      const paymentData = {
        invoice_id: 'inv_123',
        payment_method_id: 'pm_456',
        amount_cents: 10000,
        currency: 'USD',
      };

      const mockResponse = {
        success: true,
        payment_id: 'pay_789',
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await billingApi.processPayment(paymentData);

      expect(mockApi.post).toHaveBeenCalledWith('/billing/payments/process', paymentData);
      expect(result).toEqual(mockResponse);
    });

    it('returns error on payment failure', async () => {
      mockApi.post.mockRejectedValue({
        response: { data: { error: 'Payment declined' } },
      });

      const result = await billingApi.processPayment({
        invoice_id: 'inv_123',
        payment_method_id: 'pm_456',
        amount_cents: 10000,
      });

      expect(result.success).toBe(false);
      expect(result.error).toBe('Payment declined');
    });
  });

  describe('addPaymentMethod', () => {
    it('adds payment method on success', async () => {
      const paymentMethodData = {
        payment_method_id: 'pm_stripe_123',
        type: 'card',
        is_default: true,
        provider: 'stripe',
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse({ id: 'pm_new', card_brand: 'visa' }));

      const result = await billingApi.addPaymentMethod(paymentMethodData);

      expect(mockApi.post).toHaveBeenCalledWith('/billing/payment-methods', paymentMethodData);
      expect(result.success).toBe(true);
      expect(result.data).toBeDefined();
    });

    it('returns error on failure', async () => {
      mockApi.post.mockRejectedValue({
        response: { data: { error: 'Card validation failed' } },
      });

      const result = await billingApi.addPaymentMethod({
        payment_method_id: 'invalid',
      });

      expect(result.success).toBe(false);
      expect(result.error).toBe('Card validation failed');
    });
  });
});
