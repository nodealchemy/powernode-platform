import { api } from '@/shared/services/api';

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
    
    const response = await api.get<CustomersResponse>(`/customers?${params.toString()}`);
    return response.data;
  }

  // Get detailed customer information
  async getCustomer(id: string): Promise<{ customer: DetailedCustomer }> {
    const response = await api.get<{ customer: DetailedCustomer }>(`/customers/${id}`);
    return response.data;
  }

  // Create new customer
  async createCustomer(customerData: CreateCustomerRequest): Promise<{
    success: boolean;
    customer?: Customer;
    errors?: string[];
  }> {
    const response = await api.post<{
    success: boolean;
    customer?: Customer;
    errors?: string[];
  }>('/customers', { customer: customerData });
    return response.data;
  }

  // Update existing customer
  async updateCustomer(id: string, customerData: UpdateCustomerRequest): Promise<{
    success: boolean;
    customer?: Customer;
    errors?: string[];
  }> {
    const response = await api.put<{
    success: boolean;
    customer?: Customer;
    errors?: string[];
  }>(`/customers/${id}`, { customer: customerData });
    return response.data;
  }

  // Deactivate customer
  async deactivateCustomer(id: string): Promise<{ success: boolean }> {
    const response = await api.delete<{ success: boolean }>(`/customers/${id}`);
    return response.data;
  }

  // Get customer statistics
  async getCustomerStats(): Promise<CustomerStats> {
    const response = await api.get<CustomerStats>('/customers/stats');
    return response.data;
  }

}

export const customersApi = new CustomersApi();