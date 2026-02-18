// BaaS (Billing-as-a-Service) Types

export interface BaaSTenant {
  id: string;
  name: string;
  slug: string;
  status: 'pending' | 'active' | 'suspended' | 'terminated';
  tier: 'free' | 'starter' | 'pro' | 'enterprise';
  environment: 'development' | 'staging' | 'production';
  total_customers: number;
  total_subscriptions: number;
  total_invoices: number;
  total_revenue_processed: number;
  created_at: string;
}

export interface BaaSBillingConfiguration {
  stripe_connected: boolean;
  paypal_connected: boolean;
  auto_invoice: boolean;
  auto_charge: boolean;
  invoice_due_days: number;
  tax_enabled: boolean;
  dunning_enabled: boolean;
  usage_billing_enabled: boolean;
  metered_billing_enabled: boolean;
  trial_enabled: boolean;
  default_trial_days: number;
  platform_fee_percentage: number;
}

export interface BaaSDashboardStats {
  overview: {
    total_customers: number;
    total_subscriptions: number;
    total_invoices: number;
    total_revenue: number;
    active_subscriptions: number;
  };
  limits: {
    tier: string;
    max_customers: number | null;
    customers_used: number;
    max_subscriptions: number | null;
    subscriptions_used: number;
    max_api_requests: number | null;
    api_requests_today: number;
  };
  recent_activity: {
    new_customers_30d: number;
    new_subscriptions_30d: number;
    invoices_30d: number;
    revenue_30d: number;
  };
  billing_config: BaaSBillingConfiguration | null;
}

export interface BaaSApiKey {
  id: string;
  name: string;
  key_prefix: string;
  key_type: 'secret' | 'publishable' | 'restricted';
  environment: 'development' | 'staging' | 'production';
  status: 'active' | 'revoked' | 'expired';
  scopes: string[];
  total_requests: number;
  last_used_at: string | null;
  expires_at: string | null;
  created_at: string;
  key?: string; // Only present on creation
}

export interface BaaSCustomer {
  id: string;
  external_id: string;
  email: string;
  name: string;
  status: 'active' | 'archived' | 'deleted';
  currency: string;
  balance_cents: number;
  stripe_customer_id: string | null;
  active_subscriptions: number;
  total_invoices: number;
  created_at: string;
}

export interface BaaSSubscription {
  id: string;
  external_id: string;
  customer_id: string;
  plan_id: string;
  status: 'incomplete' | 'incomplete_expired' | 'trialing' | 'active' | 'past_due' | 'canceled' | 'unpaid' | 'paused';
  billing_interval: 'day' | 'week' | 'month' | 'year';
  billing_interval_count: number;
  unit_amount: number;
  currency: string;
  quantity: number;
  current_period: {
    start: string;
    end: string;
  };
  trial_end: string | null;
  cancel_at_period_end: boolean;
  stripe_subscription_id: string | null;
  created_at: string;
}

export interface BaaSInvoice {
  id: string;
  external_id: string;
  number: string;
  customer_id: string;
  subscription_id: string | null;
  status: 'draft' | 'open' | 'paid' | 'void' | 'uncollectible';
  currency: string;
  subtotal_cents: number;
  tax_cents: number;
  discount_cents: number;
  total_cents: number;
  amount_paid_cents: number;
  amount_due_cents: number;
  due_date: string | null;
  paid_at: string | null;
  period: {
    start: string;
    end: string;
  };
  line_items_count: number;
  invoice_pdf_url: string | null;
  hosted_invoice_url: string | null;
  created_at: string;
  line_items?: BaaSLineItem[];
}

export interface BaaSLineItem {
  id: string;
  description: string;
  unit_amount_cents: number;
  quantity: number;
  amount_cents: number;
  metadata: Record<string, unknown>;
}

export interface BaaSUsageRecord {
  id: string;
  customer_id: string;
  subscription_id: string | null;
  meter_id: string;
  quantity: number;
  action: 'set' | 'increment';
  timestamp: string;
  status: 'pending' | 'processed' | 'invoiced' | 'failed';
  billing_period: {
    start: string | null;
    end: string | null;
  };
}

export interface BaaSUsageSummary {
  customer_id: string;
  period: {
    start: string;
    end: string;
  };
  total_events: number;
  meters: Array<{
    meter_id: string;
    quantity: number;
  }>;
}

export interface BaaSUsageAnalytics {
  period: {
    start: string;
    end: string;
  };
  total_events: number;
  total_quantity: number;
  daily_breakdown: Array<{ date: string; quantity: number }>;
  by_meter: Array<{ meter_id: string; quantity: number }>;
  top_customers: Array<{ customer_id: string; quantity: number }>;
  by_status: Record<string, number>;
}

export interface PaginationMeta {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}
