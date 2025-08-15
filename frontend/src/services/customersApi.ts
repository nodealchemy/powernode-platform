import { api } from './api';

export interface Customer {
  id: string;
  name: string;
  subdomain: string;
  status: 'active' | 'suspended' | 'cancelled';
  created_at: string;
  updated_at: string;
  user?: {
    id: string;
    first_name: string;
    last_name: string;
    full_name: string;
    email: string;
    email_verified: boolean;
    last_login_at: string | null;
  };
  subscription?: {
    id: string;
    status: string;
    plan: {
      id: string;
      name: string;
      price_cents: number;
    };
    current_period_start: string;
    current_period_end: string;
    trial_end: string | null;
  };
  mrr: number;
  total_users: number;
}

export interface DetailedCustomer extends Customer {
  payment_methods: number;
  total_invoices: number;
  total_payments: number;
  lifetime_value: number;
  recent_activity: Array<{
    type: string;
    description: string;
    amount?: number;
    timestamp: string;
  }>;
}

export interface CustomerStats {
  total_customers: number;
  active_customers: number;
  active_subscriptions: number;
  new_this_month: number;
  total_mrr: number;
  churn_rate: number;
}

export interface CustomersResponse {
  customers: Customer[];
  pagination: {
    current_page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
  stats: CustomerStats;
}

export interface CreateCustomerRequest {
  name: string;
  subdomain?: string;
  first_name: string;
  last_name: string;
  email: string;
  plan_id?: string;
}

export interface UpdateCustomerRequest {
  name?: string;
  subdomain?: string;
  status?: 'active' | 'suspended' | 'cancelled';
  first_name?: string;
  last_name?: string;
  email?: string;
  subscription_attributes?: {
    plan_id?: string;
    status?: string;
  };
}

class CustomersApi {
  // Get customers with pagination and filtering
  async getCustomers(options: {
    page?: number;
    per_page?: number;
    search?: string;
    status?: string;
    plan?: string;
  } = {}): Promise<CustomersResponse> {
    const params = new URLSearchParams();
    
    if (options.page) params.set('page', options.page.toString());
    if (options.per_page) params.set('per_page', options.per_page.toString());
    if (options.search) params.set('search', options.search);
    if (options.status && options.status !== 'all') params.set('status', options.status);
    if (options.plan && options.plan !== 'all') params.set('plan', options.plan);
    
    const response = await api.get(`/customers?${params.toString()}`);
    return response.data;
  }

  // Get detailed customer information
  async getCustomer(id: string): Promise<{ customer: DetailedCustomer }> {
    const response = await api.get(`/customers/${id}`);
    return response.data;
  }

  // Create new customer
  async createCustomer(customerData: CreateCustomerRequest): Promise<{
    success: boolean;
    customer?: Customer;
    errors?: string[];
  }> {
    const response = await api.post('/customers', { customer: customerData });
    return response.data;
  }

  // Update existing customer
  async updateCustomer(id: string, customerData: UpdateCustomerRequest): Promise<{
    success: boolean;
    customer?: Customer;
    errors?: string[];
  }> {
    const response = await api.put(`/customers/${id}`, { customer: customerData });
    return response.data;
  }

  // Deactivate customer
  async deactivateCustomer(id: string): Promise<{ success: boolean }> {
    const response = await api.delete(`/customers/${id}`);
    return response.data;
  }

  // Get customer statistics
  async getCustomerStats(): Promise<CustomerStats> {
    const response = await api.get('/customers/stats');
    return response.data;
  }

  // Utility methods
  formatCurrency(amountCents: number, currency = 'USD'): string {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency.toUpperCase(),
    }).format(amountCents / 100);
  }

  getStatusColor(status: string): 'green' | 'yellow' | 'red' | 'gray' {
    switch (status) {
      case 'active':
        return 'green';
      case 'suspended':
        return 'yellow';
      case 'cancelled':
        return 'red';
      default:
        return 'gray';
    }
  }

  getStatusText(status: string): string {
    switch (status) {
      case 'active':
        return 'Active';
      case 'suspended':
        return 'Suspended';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.charAt(0).toUpperCase() + status.slice(1);
    }
  }

  getSubscriptionStatusColor(status: string): 'green' | 'yellow' | 'red' | 'blue' | 'gray' {
    switch (status) {
      case 'active':
        return 'green';
      case 'trialing':
        return 'blue';
      case 'past_due':
        return 'yellow';
      case 'cancelled':
      case 'unpaid':
        return 'red';
      default:
        return 'gray';
    }
  }

  formatSubscriptionStatus(status: string): string {
    switch (status) {
      case 'trialing':
        return 'Trial';
      case 'past_due':
        return 'Past Due';
      default:
        return status.charAt(0).toUpperCase() + status.slice(1);
    }
  }

  calculateMrrDisplay(mrr: number): string {
    if (mrr === 0) return '$0';
    return this.formatCurrency(mrr);
  }

  formatJoinDate(dateString: string): string {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  }

  formatRelativeTime(dateString: string | null): string {
    if (!dateString) return 'Never';
    
    const date = new Date(dateString);
    const now = new Date();
    const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);
    
    if (diffInSeconds < 60) return 'Just now';
    if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)}m ago`;
    if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)}h ago`;
    if (diffInSeconds < 604800) return `${Math.floor(diffInSeconds / 86400)}d ago`;
    
    return date.toLocaleDateString();
  }
}

export const customersApi = new CustomersApi();