// Common types used across the application

export interface Plan {
  id: string;
  name: string;
  description: string;
  price_cents: number;
  currency: string;
  billing_cycle: 'monthly' | 'yearly' | 'quarterly';
  status: 'active' | 'inactive' | 'archived';
  trial_days: number;
  is_public: boolean;
  formatted_price: string;
  monthly_price: string;
  subscription_count?: number;
  active_subscription_count?: number;
  can_be_deleted?: boolean;
  has_annual_discount?: boolean;
  annual_discount_percent?: number;
  has_promotional_discount?: boolean;
  promotional_discount_percent?: number;
  promotional_discount_start?: string | null;
  promotional_discount_end?: string | null;
  promotional_discount_code?: string | null;
  has_volume_discount?: boolean;
  volume_discount_tiers?: VolumeDiscountTier[];
  annual_savings_amount?: string;
  annual_savings_percentage?: number;
  features?: Record<string, unknown>;
  limits?: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface VolumeDiscountTier {
  min_quantity: number;
  discount_percent: number;
}

export interface DetailedPlan extends Plan {
  features: Record<string, unknown>;
  limits: Record<string, unknown>;
  default_role: string;
  metadata: Record<string, unknown>;
  stripe_price_id: string | null;
  paypal_plan_id: string | null;
  can_be_deleted: boolean;
  has_annual_discount: boolean;
  annual_discount_percent: number;
  has_volume_discount: boolean;
  volume_discount_tiers: VolumeDiscountTier[];
  has_promotional_discount: boolean;
  promotional_discount_percent: number;
  promotional_discount_start: string | null;
  promotional_discount_end: string | null;
  promotional_discount_code: string | null;
  annual_savings_amount: string;
  annual_savings_percentage: number;
}

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

// Backward compatibility alias
export type { Plan as SubscriptionPlan };

export interface Subscription {
  id: string;
  status: string;
  current_period_start: string;
  current_period_end: string;
  trial_start?: string;
  trial_end?: string;
  canceled_at?: string;
  ends_at?: string;
  plan: Plan;
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