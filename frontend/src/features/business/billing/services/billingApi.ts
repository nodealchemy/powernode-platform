import { api } from '@/shared/services/api';
import { getErrorMessage } from '@/shared/utils/errorHandling';

export interface BillingOverview {
  outstanding?: number;
  this_month?: number;
  collected?: number;
  success_rate?: number;
  recent_invoices?: Invoice[];
  payment_methods?: PaymentMethod[];
}

export interface Invoice {
  id: string;
  invoice_number: string;
  subtotal: string;
  tax_amount?: string;
  total_amount: string;
  currency: string;
  status: 'draft' | 'sent' | 'paid' | 'overdue' | 'canceled';
  due_date: string;
  created_at: string;
  line_items_count?: number;
}

export interface PaymentMethod {
  id: string;
  provider: 'stripe' | 'paypal';
  payment_method_type: string;
  card_brand?: string;
  card_last_four?: string;
  bank_account_last_four?: string;
  is_default: boolean;
  created_at?: string;
}

export interface SubscriptionBilling {
  subscription: {
    id: string;
    plan: {
      id: string;
      name: string;
      price: string;
      billing_cycle: string;
    };
    status: string;
    current_period_start: string;
    current_period_end: string;
    trial_end?: string;
    canceled_at?: string;
  };
  upcoming_invoice?: {
    amount_due: number;
    currency: string;
    next_payment_date: string;
    description: string;
  };
  billing_history: Array<{
    id: string;
    invoice_number: string;
    amount: string;
    status: string;
    created_at: string;
  }>;
}

export interface CreateInvoiceRequest {
  currency: string;
  due_date: string;
  notes?: string;
  line_items: Array<{
    description: string;
    quantity: number;
    unit_price: number;
  }>;
}

export interface PaymentIntentRequest {
  amount_cents: number;
  currency?: string;
  description?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    current_page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
}

/**
 * @module BillingApi
 * @description Billing operations, invoices, and payment processing service.
 *
 * RESPONSIBILITY: Billing overview, invoices, payment methods, payment processing
 * NOT RESPONSIBLE FOR: Subscription CRUD operations
 *
 * @see Use subscriptionService for subscription lifecycle management
 */
class BillingApi {
  // Get billing overview with summary statistics
  async getOverview(): Promise<BillingOverview> {
    try {
      const response = await api.get('/billing');
      return response.data;
    } catch (error) {
      const message = getErrorMessage(error);
      throw new Error(message);
    }
  }

  // Get subscription billing information
  async getSubscriptionBilling(): Promise<SubscriptionBilling> {
    try {
      const response = await api.get('/billing/subscription');
      return response.data;
    } catch (error) {
      const message = getErrorMessage(error);
      throw new Error(message);
    }
  }

  // Get invoices with pagination
  async getInvoices(page = 1, perPage = 20): Promise<PaginatedResponse<Invoice>> {
    try {
      const response = await api.get('/billing/invoices', {
        params: { page, per_page: perPage }
      });
      return {
        data: response.data.invoices,
        pagination: response.data.pagination
      };
    } catch (error) {
      const message = getErrorMessage(error);
      throw new Error(message);
    }
  }

  // Create new invoice
  async createInvoice(invoiceData: CreateInvoiceRequest): Promise<{
    success: boolean;
    invoice?: {
      id: string;
      invoice_number: string;
      total_amount: string;
      status: string;
    };
    errors?: string[];
    error?: string;
  }> {
    try {
      const response = await api.post('/billing/invoices', {
        invoice: {
          currency: invoiceData.currency,
          due_date: invoiceData.due_date,
          notes: invoiceData.notes
        },
        line_items: invoiceData.line_items
      });
      return response.data;
    } catch (error) {
      const message = getErrorMessage(error);
      return { success: false, error: message, errors: [message] };
    }
  }

  // Get payment methods
  async getPaymentMethods(): Promise<{ data: PaymentMethod[]; error?: string }> {
    try {
      const response = await api.get('/billing/payment-methods');
      return { data: response.data.payment_methods || response.data };
    } catch (error) {
      const message = getErrorMessage(error);
      return { data: [], error: message };
    }
  }

  // Add payment method
  async createPaymentMethod(paymentMethodId: string, provider = 'stripe'): Promise<{
    success: boolean;
    payment_method?: PaymentMethod;
    error?: string;
  }> {
    try {
      const response = await api.post('/billing/payment-methods', {
        payment_method_id: paymentMethodId,
        provider
      });
      return response.data;
    } catch (error) {
      const message = getErrorMessage(error);
      return { success: false, error: message };
    }
  }

  // Create payment intent for one-time payments
  async createPaymentIntent(request: PaymentIntentRequest): Promise<{
    success: boolean;
    client_secret?: string;
    payment_intent_id?: string;
    error?: string;
  }> {
    try {
      const response = await api.post('/billing/payment-intent', request);
      return response.data;
    } catch (error) {
      const message = getErrorMessage(error);
      return { success: false, error: message };
    }
  }

  // Additional payment method methods for test compatibility
  async addPaymentMethod(paymentMethodData: {
    payment_method_id?: string;
    type?: string;
    token?: string;
    is_default?: boolean;
    provider?: string;
  }): Promise<{
    success: boolean;
    data?: PaymentMethod | { payment_methods: PaymentMethod[] };
    payment_method?: PaymentMethod;
    error?: string;
  }> {
    try {
      const response = await api.post('/billing/payment-methods', paymentMethodData);
      return { success: true, data: response.data };
    } catch (error) {
      const message = getErrorMessage(error);
      return { success: false, error: message };
    }
  }

  async removePaymentMethod(paymentMethodId: string): Promise<{
    success: boolean;
    error?: string;
  }> {
    try {
      const response = await api.delete(`/billing/payment-methods/${paymentMethodId}`);
      return { success: true, ...response.data };
    } catch (error) {
      const message = getErrorMessage(error);
      return { success: false, error: message };
    }
  }

  async setDefaultPaymentMethod(paymentMethodId: string): Promise<{
    success: boolean;
    error?: string;
  }> {
    try {
      const response = await api.put(`/billing/payment-methods/${paymentMethodId}/default`);
      return { success: true, ...response.data };
    } catch (error) {
      const message = getErrorMessage(error);
      return { success: false, error: message };
    }
  }

  // Billing history
  async getBillingHistory(filters?: {
    start_date?: string;
    end_date?: string;
    page?: number;
    per_page?: number;
  }): Promise<{
    data: Array<{
      id: string;
      invoice_number: string;
      amount: string;
      status: string;
      created_at: string;
    }>;
    pagination?: {
      current_page: number;
      per_page: number;
      total_count: number;
      total_pages: number;
    };
    error?: string;
  }> {
    try {
      const response = filters && Object.keys(filters).length > 0 ?
        await api.get('/billing/history', { params: filters }) :
        await api.get('/billing/history');
      return { data: response.data.data || response.data, pagination: response.data.pagination };
    } catch (error) {
      const message = getErrorMessage(error);
      return { data: [], error: message };
    }
  }

  // Process payment method for test compatibility
  async processPayment(paymentData: {
    invoice_id: string;
    payment_method_id: string;
    amount_cents: number;
    currency?: string;
  }): Promise<{
    success: boolean;
    payment_id?: string;
    error?: string;
  }> {
    try {
      const response = await api.post('/billing/payments/process', paymentData);
      return response.data;
    } catch (error) {
      const message = getErrorMessage(error);
      return { success: false, error: message };
    }
  }
}

export const billingApi = new BillingApi();