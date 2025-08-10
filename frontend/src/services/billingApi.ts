import { api } from './api';

export interface BillingOverview {
  outstanding: number;
  this_month: number;
  collected: number;
  success_rate: number;
  recent_invoices: Invoice[];
  payment_methods: PaymentMethod[];
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

class BillingApi {
  // Get billing overview with summary statistics
  async getOverview(): Promise<BillingOverview> {
    const response = await api.get('/billing');
    return response.data;
  }

  // Get subscription billing information
  async getSubscriptionBilling(): Promise<SubscriptionBilling> {
    const response = await api.get('/billing/subscription');
    return response.data;
  }

  // Get invoices with pagination
  async getInvoices(page = 1, perPage = 20): Promise<PaginatedResponse<Invoice>> {
    const response = await api.get('/billing/invoices', {
      params: { page, per_page: perPage }
    });
    return {
      data: response.data.invoices,
      pagination: response.data.pagination
    };
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
  }> {
    const response = await api.post('/billing/invoices', {
      invoice: {
        currency: invoiceData.currency,
        due_date: invoiceData.due_date,
        notes: invoiceData.notes
      },
      line_items: invoiceData.line_items
    });
    return response.data;
  }

  // Get payment methods
  async getPaymentMethods(): Promise<{ payment_methods: PaymentMethod[] }> {
    const response = await api.get('/billing/payment-methods');
    return response.data;
  }

  // Add payment method
  async createPaymentMethod(paymentMethodId: string, provider = 'stripe'): Promise<{
    success: boolean;
    payment_method?: PaymentMethod;
    error?: string;
  }> {
    const response = await api.post('/billing/payment-methods', {
      payment_method_id: paymentMethodId,
      provider
    });
    return response.data;
  }

  // Create payment intent for one-time payments
  async createPaymentIntent(request: PaymentIntentRequest): Promise<{
    success: boolean;
    client_secret?: string;
    payment_intent_id?: string;
    error?: string;
  }> {
    const response = await api.post('/billing/payment-intent', request);
    return response.data;
  }

  // Utility methods
  formatCurrency(amountCents: number | string, currency = 'USD'): string {
    const amount = typeof amountCents === 'string' ? parseInt(amountCents) : amountCents;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency.toUpperCase(),
    }).format(amount / 100);
  }

  getStatusColor(status: string): 'green' | 'yellow' | 'red' | 'blue' | 'gray' {
    switch (status) {
      case 'paid':
      case 'succeeded':
        return 'green';
      case 'sent':
      case 'processing':
        return 'blue';
      case 'draft':
        return 'yellow';
      case 'overdue':
      case 'failed':
        return 'red';
      default:
        return 'gray';
    }
  }

  getStatusText(status: string): string {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'paid':
        return 'Paid';
      case 'overdue':
        return 'Overdue';
      case 'canceled':
        return 'Canceled';
      case 'succeeded':
        return 'Succeeded';
      case 'failed':
        return 'Failed';
      case 'processing':
        return 'Processing';
      default:
        return status.charAt(0).toUpperCase() + status.slice(1);
    }
  }

  getPaymentMethodDisplay(method: PaymentMethod): string {
    if (method.card_brand && method.card_last_four) {
      return `${method.card_brand.toUpperCase()} •••• ${method.card_last_four}`;
    }
    if (method.bank_account_last_four) {
      return `Bank •••• ${method.bank_account_last_four}`;
    }
    return `${method.provider} ${method.payment_method_type}`;
  }
}

export const billingApi = new BillingApi();