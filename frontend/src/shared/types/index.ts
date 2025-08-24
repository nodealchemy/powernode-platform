// Common types used across the application

export interface APIResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
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
  features: Record<string, any>;
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