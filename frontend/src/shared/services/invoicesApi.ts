import { api } from '@/shared/services/api';

export interface Invoice {
  id: string;
  invoice_number: string;
  account_id: string;
  subscription_id?: string;
  status: 'draft' | 'open' | 'paid' | 'void' | 'uncollectible' | 'overdue';
  amount_due: number;
  amount_paid: number;
  amount_remaining: number;
  subtotal: number;
  tax_amount: number;
  total: number;
  currency: string;
  description?: string;
  due_date: string;
  issue_date: string;
  paid_at?: string;
  voided_at?: string;
  created_at: string;
  updated_at: string;
  
  // Customer info
  customer: {
    id: string;
    name: string;
    email: string;
    billing_address?: Address;
  };
  
  // Line items
  line_items: InvoiceLineItem[];
  
  // Payment info
  payment_attempts: PaymentAttempt[];
  last_payment_attempt?: PaymentAttempt;
  
  // Metadata
  metadata?: Record<string, unknown>;
  
  // URLs
  hosted_invoice_url?: string;
  invoice_pdf_url?: string;
}

export interface InvoiceLineItem {
  id: string;
  description: string;
  quantity: number;
  unit_amount: number;
  amount: number;
  tax_amount: number;
  period_start?: string;
  period_end?: string;
  proration?: boolean;
  metadata?: Record<string, unknown>;
}

export interface PaymentAttempt {
  id: string;
  amount: number;
  currency: string;
  status: 'pending' | 'succeeded' | 'failed' | 'canceled';
  payment_method?: string;
  failure_code?: string;
  failure_message?: string;
  created_at: string;
  gateway_transaction_id?: string;
}

export interface Address {
  line1: string;
  line2?: string;
  city: string;
  state?: string;
  postal_code: string;
  country: string;
}

export interface InvoiceFilters {
  status?: string[];
  customer_id?: string;
  subscription_id?: string;
  date_range?: {
    start_date: string;
    end_date: string;
  };
  amount_range?: {
    min_amount: number;
    max_amount: number;
  };
  overdue_only?: boolean;
  sort_by?: 'created_at' | 'due_date' | 'amount_due' | 'status';
  sort_order?: 'asc' | 'desc';
}

export interface InvoicesListResponse {
  success: boolean;
  invoices: Invoice[];
  pagination: {
    current_page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
  summary: {
    total_amount: number;
    paid_amount: number;
    outstanding_amount: number;
    overdue_amount: number;
    invoice_count: number;
  };
}

export interface InvoiceResponse {
  success: boolean;
  invoice?: Invoice;
  message?: string;
  error?: string;
}

export interface CreateInvoiceRequest {
  customer_id: string;
  subscription_id?: string;
  description?: string;
  due_date?: string;
  line_items: {
    description: string;
    quantity: number;
    unit_amount: number;
    tax_rate?: number;
  }[];
  metadata?: Record<string, unknown>;
  auto_send?: boolean;
}

export interface InvoiceStats {
  total_invoices: number;
  total_amount: number;
  paid_amount: number;
  outstanding_amount: number;
  overdue_amount: number;
  average_payment_time: number;
  payment_success_rate: number;
  monthly_revenue: number;
  pending_invoices: number;
  overdue_invoices: number;
}

export const invoicesApi = {
  // Get list of invoices with filtering and pagination
  async getInvoices(
    page = 1,
    perPage = 20,
    filters: InvoiceFilters = {}
  ): Promise<InvoicesListResponse> {
    const response = await api.get('/api/v1/invoices', {
      params: {
        page,
        per_page: perPage,
        ...filters
      }
    });
    return response.data;
  },

  // Get specific invoice by ID
  async getInvoice(id: string): Promise<InvoiceResponse> {
    const response = await api.get(`/api/v1/invoices/${id}`);
    return response.data;
  },

  // Create new invoice
  async createInvoice(invoiceData: CreateInvoiceRequest): Promise<InvoiceResponse> {
    const response = await api.post('/api/v1/invoices', invoiceData);
    return response.data;
  },

  // Update invoice (only for draft invoices)
  async updateInvoice(id: string, updates: Partial<CreateInvoiceRequest>): Promise<InvoiceResponse> {
    const response = await api.put(`/api/v1/invoices/${id}`, updates);
    return response.data;
  },

  // Delete invoice (only for draft invoices)
  async deleteInvoice(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    const response = await api.delete(`/api/v1/invoices/${id}`);
    return response.data;
  },

  // Send invoice to customer
  async sendInvoice(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    const response = await api.post(`/api/v1/invoices/${id}/send`);
    return response.data;
  },

  // Mark invoice as paid (manual payment)
  async markAsPaid(
    id: string,
    paymentDetails: {
      amount: number;
      payment_method: string;
      payment_date?: string;
      notes?: string;
    }
  ): Promise<InvoiceResponse> {
    const response = await api.post(`/api/v1/invoices/${id}/mark_paid`, paymentDetails);
    return response.data;
  },

  // Void invoice
  async voidInvoice(id: string, reason?: string): Promise<InvoiceResponse> {
    const response = await api.post(`/api/v1/invoices/${id}/void`, { reason });
    return response.data;
  },

  // Retry payment for invoice
  async retryPayment(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    const response = await api.post(`/api/v1/invoices/${id}/retry_payment`);
    return response.data;
  },

  // Get invoice PDF
  async downloadPDF(id: string): Promise<Blob> {
    const response = await api.get(`/api/v1/invoices/${id}/pdf`, {
      responseType: 'blob'
    });
    return response.data;
  },

  // Get invoice statistics
  async getInvoiceStats(): Promise<InvoiceStats> {
    const response = await api.get('/api/v1/invoices/statistics');
    return response.data;
  },

  // Get overdue invoices
  async getOverdueInvoices(page = 1, perPage = 20): Promise<InvoicesListResponse> {
    return this.getInvoices(page, perPage, { 
      overdue_only: true,
      sort_by: 'due_date',
      sort_order: 'asc'
    });
  },

  isOverdue(invoice: Invoice): boolean {
    if (invoice.status === 'paid' || invoice.status === 'void') {
      return false;
    }
    const dueDate = new Date(invoice.due_date);
    const now = new Date();
    return dueDate < now;
  },

  getDaysOverdue(invoice: Invoice): number {
    if (!this.isOverdue(invoice)) {
      return 0;
    }
    const dueDate = new Date(invoice.due_date);
    const now = new Date();
    const diffTime = now.getTime() - dueDate.getTime();
    return Math.ceil(diffTime / (1000 * 60 * 60 * 24));
  },

  calculateTotal(lineItems: InvoiceLineItem[]): number {
    return lineItems.reduce((total, item) => total + item.amount + item.tax_amount, 0);
  }
};

export default invoicesApi;