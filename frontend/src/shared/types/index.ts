// Common types used across the application

export interface APIResponse<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface APIError {
  message: string;
  status?: number;
  code?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    per_page: number;
    total: number;
    pages: number;
  };
}

export interface DateRange {
  start_date: string;
  end_date: string;
}

// Analytics types
export interface RevenueMetrics {
  mrr: number;
  arr: number;
  active_subscriptions: number;
  total_customers: number;
  arpu: number;
  growth_rate: number;
}

export interface ChurnMetrics {
  customer_churn_rate: number;
  revenue_churn_rate: number;
  churned_customers: number;
  churned_subscriptions: number;
}

export interface SubscriptionPlan {
  id: string;
  name: string;
  description: string;
  price_cents: number;
  currency: string;
  billing_cycle: 'monthly' | 'quarterly' | 'yearly';
  trial_days: number;
  features: Record<string, boolean | string | number>;
  limits: Record<string, number>;
  status: 'active' | 'inactive' | 'archived';
}

export interface Subscription {
  id: string;
  status: string;
  current_period_start: string;
  current_period_end: string;
  trial_start?: string;
  trial_end?: string;
  plan: SubscriptionPlan;
  created_at: string;
  updated_at: string;
}

export interface Invoice {
  id: string;
  number: string;
  status: string;
  amount_cents: number;
  currency: string;
  due_date: string;
  paid_at?: string;
  created_at: string;
}

export interface PaymentMethod {
  id: string;
  type: 'stripe' | 'paypal';
  last_four?: string;
  brand?: string;
  exp_month?: number;
  exp_year?: number;
  is_default: boolean;
  created_at: string;
}

// Additional shared interfaces for common patterns
export interface PaymentGatewayConfig {
  id: string;
  gateway_type: 'stripe' | 'paypal';
  is_enabled: boolean;
  is_default: boolean;
  configuration: {
    publishable_key?: string;
    webhook_secret?: string;
    client_id?: string;
    client_secret?: string;
    environment?: 'sandbox' | 'production';
  };
  created_at: string;
  updated_at: string;
}

export interface SiteSetting {
  id: string;
  key: string;
  value: string;
  parsed_value: string | number | boolean | object;
  setting_type: 'string' | 'number' | 'boolean' | 'json';
  created_at: string;
  updated_at: string;
}

export interface WorkerJobData {
  job_id?: string;
  action: string;
  parameters: Record<string, unknown>;
  priority?: 'low' | 'normal' | 'high' | 'critical';
}

export interface FormErrorState {
  message: string;
  field?: string;
}