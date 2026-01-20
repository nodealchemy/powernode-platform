import api from '@/shared/api/api';
import type {
  BaaSTenant,
  BaaSBillingConfiguration,
  BaaSDashboardStats,
  BaaSApiKey,
  BaaSCustomer,
  BaaSSubscription,
  BaaSInvoice,
  BaaSUsageRecord,
  BaaSUsageSummary,
  BaaSUsageAnalytics,
  PaginationMeta,
} from '../types';

const BASE_URL = '/api/baas/v1';

interface PaginatedResponse<T> {
  data: T[];
  meta: { pagination: PaginationMeta };
}

// ==================== Tenant ====================

export const getTenant = async (): Promise<{ data: BaaSTenant }> => {
  const response = await api.get(`${BASE_URL}/tenant`);
  return response.data;
};

export const createTenant = async (data: {
  name: string;
  slug?: string;
  tier?: string;
  environment?: string;
  webhook_url?: string;
  default_currency?: string;
  timezone?: string;
}): Promise<{ data: BaaSTenant }> => {
  const response = await api.post(`${BASE_URL}/tenant`, data);
  return response.data;
};

export const updateTenant = async (data: Partial<BaaSTenant>): Promise<{ data: BaaSTenant }> => {
  const response = await api.patch(`${BASE_URL}/tenant`, data);
  return response.data;
};

export const getTenantDashboard = async (): Promise<{ data: BaaSDashboardStats }> => {
  const response = await api.get(`${BASE_URL}/tenant/dashboard`);
  return response.data;
};

export const getTenantLimits = async (): Promise<{ data: Record<string, unknown> }> => {
  const response = await api.get(`${BASE_URL}/tenant/limits`);
  return response.data;
};

export const getBillingConfiguration = async (): Promise<{ data: BaaSBillingConfiguration }> => {
  const response = await api.get(`${BASE_URL}/tenant/billing_configuration`);
  return response.data;
};

export const updateBillingConfiguration = async (
  data: Partial<BaaSBillingConfiguration>
): Promise<{ data: BaaSBillingConfiguration }> => {
  const response = await api.patch(`${BASE_URL}/tenant/billing_configuration`, data);
  return response.data;
};

// ==================== API Keys ====================

export const getApiKeys = async (params?: {
  environment?: string;
  key_type?: string;
  status?: string;
}): Promise<{ data: BaaSApiKey[] }> => {
  const response = await api.get(`${BASE_URL}/api_keys`, { params });
  return response.data;
};

export const createApiKey = async (data: {
  name: string;
  key_type?: string;
  environment?: string;
  scopes?: string[];
  rate_limit_per_minute?: number;
  rate_limit_per_day?: number;
  expires_at?: string;
}): Promise<{ data: BaaSApiKey; message: string }> => {
  const response = await api.post(`${BASE_URL}/api_keys`, data);
  return response.data;
};

export const updateApiKey = async (
  id: string,
  data: Partial<BaaSApiKey>
): Promise<{ data: BaaSApiKey }> => {
  const response = await api.patch(`${BASE_URL}/api_keys/${id}`, data);
  return response.data;
};

export const revokeApiKey = async (id: string): Promise<{ message: string }> => {
  const response = await api.delete(`${BASE_URL}/api_keys/${id}`);
  return response.data;
};

export const rollApiKey = async (id: string): Promise<{ data: BaaSApiKey; message: string }> => {
  const response = await api.post(`${BASE_URL}/api_keys/${id}/roll`);
  return response.data;
};

// ==================== Customers ====================

export const getCustomers = async (params?: {
  status?: string;
  email?: string;
  page?: number;
  per_page?: number;
}): Promise<PaginatedResponse<BaaSCustomer>> => {
  const response = await api.get(`${BASE_URL}/customers`, { params });
  return response.data;
};

export const getCustomer = async (id: string): Promise<{ data: BaaSCustomer }> => {
  const response = await api.get(`${BASE_URL}/customers/${id}`);
  return response.data;
};

export const createCustomer = async (data: {
  external_id?: string;
  email: string;
  name?: string;
  currency?: string;
  metadata?: Record<string, unknown>;
}): Promise<{ data: BaaSCustomer }> => {
  const response = await api.post(`${BASE_URL}/customers`, data);
  return response.data;
};

export const updateCustomer = async (
  id: string,
  data: Partial<BaaSCustomer>
): Promise<{ data: BaaSCustomer }> => {
  const response = await api.patch(`${BASE_URL}/customers/${id}`, data);
  return response.data;
};

export const archiveCustomer = async (id: string): Promise<{ message: string }> => {
  const response = await api.delete(`${BASE_URL}/customers/${id}`);
  return response.data;
};

// ==================== Subscriptions ====================

export const getSubscriptions = async (params?: {
  status?: string;
  customer_id?: string;
  page?: number;
  per_page?: number;
}): Promise<PaginatedResponse<BaaSSubscription>> => {
  const response = await api.get(`${BASE_URL}/subscriptions`, { params });
  return response.data;
};

export const getSubscription = async (id: string): Promise<{ data: BaaSSubscription }> => {
  const response = await api.get(`${BASE_URL}/subscriptions/${id}`);
  return response.data;
};

export const createSubscription = async (data: {
  customer_id: string;
  plan_id: string;
  external_id?: string;
  billing_interval?: string;
  unit_amount?: number;
  currency?: string;
  quantity?: number;
  trial_days?: number;
}): Promise<{ data: BaaSSubscription }> => {
  const response = await api.post(`${BASE_URL}/subscriptions`, data);
  return response.data;
};

export const updateSubscription = async (
  id: string,
  data: Partial<BaaSSubscription>
): Promise<{ data: BaaSSubscription }> => {
  const response = await api.patch(`${BASE_URL}/subscriptions/${id}`, data);
  return response.data;
};

export const cancelSubscription = async (
  id: string,
  data?: { reason?: string; at_period_end?: boolean }
): Promise<{ data: BaaSSubscription; message: string }> => {
  const response = await api.post(`${BASE_URL}/subscriptions/${id}/cancel`, data);
  return response.data;
};

export const pauseSubscription = async (id: string): Promise<{ data: BaaSSubscription; message: string }> => {
  const response = await api.post(`${BASE_URL}/subscriptions/${id}/pause`);
  return response.data;
};

export const resumeSubscription = async (id: string): Promise<{ data: BaaSSubscription; message: string }> => {
  const response = await api.post(`${BASE_URL}/subscriptions/${id}/resume`);
  return response.data;
};

// ==================== Invoices ====================

export const getInvoices = async (params?: {
  status?: string;
  customer_id?: string;
  page?: number;
  per_page?: number;
}): Promise<PaginatedResponse<BaaSInvoice>> => {
  const response = await api.get(`${BASE_URL}/invoices`, { params });
  return response.data;
};

export const getInvoice = async (id: string): Promise<{ data: BaaSInvoice }> => {
  const response = await api.get(`${BASE_URL}/invoices/${id}`);
  return response.data;
};

export const createInvoice = async (data: {
  customer_id: string;
  subscription_id?: string;
  currency?: string;
  due_date?: string;
  line_items?: Array<{
    description: string;
    amount_cents?: number;
    amount?: number;
    quantity?: number;
  }>;
}): Promise<{ data: BaaSInvoice }> => {
  const response = await api.post(`${BASE_URL}/invoices`, data);
  return response.data;
};

export const finalizeInvoice = async (id: string): Promise<{ data: BaaSInvoice; message: string }> => {
  const response = await api.post(`${BASE_URL}/invoices/${id}/finalize`);
  return response.data;
};

export const payInvoice = async (
  id: string,
  data?: { payment_reference?: string }
): Promise<{ data: BaaSInvoice; message: string }> => {
  const response = await api.post(`${BASE_URL}/invoices/${id}/pay`, data);
  return response.data;
};

export const voidInvoice = async (
  id: string,
  data?: { reason?: string }
): Promise<{ data: BaaSInvoice; message: string }> => {
  const response = await api.post(`${BASE_URL}/invoices/${id}/void`, data);
  return response.data;
};

// ==================== Usage ====================

export const recordUsageEvent = async (data: {
  customer_id: string;
  meter_id: string;
  quantity: number;
  action?: 'set' | 'increment';
  idempotency_key?: string;
  timestamp?: string;
}): Promise<{ data: BaaSUsageRecord }> => {
  const response = await api.post(`${BASE_URL}/usage_events`, data);
  return response.data;
};

export const recordUsageBatch = async (
  events: Array<{
    customer_id: string;
    meter_id: string;
    quantity: number;
    action?: 'set' | 'increment';
    idempotency_key?: string;
    timestamp?: string;
  }>
): Promise<{ data: { successful: number; failed: number; errors: unknown[] } }> => {
  const response = await api.post(`${BASE_URL}/usage_events/batch`, { events });
  return response.data;
};

export const getUsageRecords = async (params?: {
  customer_id?: string;
  meter_id?: string;
  status?: string;
  start_date?: string;
  end_date?: string;
  page?: number;
  per_page?: number;
}): Promise<PaginatedResponse<BaaSUsageRecord>> => {
  const response = await api.get(`${BASE_URL}/usage`, { params });
  return response.data;
};

export const getUsageSummary = async (params: {
  customer_id: string;
  start_date?: string;
  end_date?: string;
}): Promise<{ data: BaaSUsageSummary }> => {
  const response = await api.get(`${BASE_URL}/usage/summary`, { params });
  return response.data;
};

export const getUsageAggregate = async (params: {
  customer_id: string;
  meter_id: string;
  start_date?: string;
  end_date?: string;
}): Promise<{ data: { customer_id: string; meter_id: string; period: { start: string; end: string }; total_quantity: number } }> => {
  const response = await api.get(`${BASE_URL}/usage/aggregate`, { params });
  return response.data;
};

export const getUsageAnalytics = async (params?: {
  start_date?: string;
  end_date?: string;
}): Promise<{ data: BaaSUsageAnalytics }> => {
  const response = await api.get(`${BASE_URL}/usage/analytics`, { params });
  return response.data;
};

export default {
  // Tenant
  getTenant,
  createTenant,
  updateTenant,
  getTenantDashboard,
  getTenantLimits,
  getBillingConfiguration,
  updateBillingConfiguration,
  // API Keys
  getApiKeys,
  createApiKey,
  updateApiKey,
  revokeApiKey,
  rollApiKey,
  // Customers
  getCustomers,
  getCustomer,
  createCustomer,
  updateCustomer,
  archiveCustomer,
  // Subscriptions
  getSubscriptions,
  getSubscription,
  createSubscription,
  updateSubscription,
  cancelSubscription,
  pauseSubscription,
  resumeSubscription,
  // Invoices
  getInvoices,
  getInvoice,
  createInvoice,
  finalizeInvoice,
  payInvoice,
  voidInvoice,
  // Usage
  recordUsageEvent,
  recordUsageBatch,
  getUsageRecords,
  getUsageSummary,
  getUsageAggregate,
  getUsageAnalytics,
};
