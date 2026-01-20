export interface UsageMeter {
  id: string;
  name: string;
  slug: string;
  description?: string;
  unit_name: string;
  aggregation_type: AggregationType;
  billing_model: BillingModel;
  reset_period: ResetPeriod;
  is_active: boolean;
  is_billable: boolean;
  pricing_tiers?: PricingTier[];
}

export type AggregationType = 'sum' | 'max' | 'count' | 'last' | 'average';
export type BillingModel = 'tiered' | 'volume' | 'package' | 'flat' | 'per_unit';
export type ResetPeriod = 'never' | 'daily' | 'weekly' | 'monthly' | 'yearly' | 'billing_period';

export interface PricingTier {
  from?: number;
  to?: number;
  price_per_unit?: number;
  price?: number;
  package_size?: number;
}

export interface UsageEvent {
  id: string;
  event_id: string;
  meter_slug: string;
  quantity: number;
  timestamp: string;
  source?: UsageEventSource;
  is_processed: boolean;
  properties?: Record<string, unknown>;
}

export type UsageEventSource = 'api' | 'webhook' | 'system' | 'import' | 'internal';

export interface UsageQuota {
  id: string;
  meter_name: string;
  meter_slug: string;
  soft_limit?: number;
  hard_limit?: number;
  current_usage: number;
  remaining?: number;
  usage_percent: number;
  exceeded: boolean;
  allow_overage: boolean;
  overage_rate?: number;
  overage_amount?: number;
  warning_threshold_percent?: number;
  critical_threshold_percent?: number;
  at_warning: boolean;
  at_critical: boolean;
  current_period_start?: string;
  current_period_end?: string;
  unit_name: string;
}

export interface UsageSummary {
  id: string;
  meter_name: string;
  meter_slug: string;
  period_start: string;
  period_end: string;
  total_quantity: number;
  billable_quantity: number;
  event_count: number;
  quota_limit?: number;
  quota_used?: number;
  quota_exceeded: boolean;
  quota_usage_percent: number;
  overage_quantity: number;
  calculated_amount: number;
  is_billed: boolean;
  unit_name: string;
}

export interface UsageDashboardData {
  account_id: string;
  period: {
    start: string;
    end: string;
  };
  meters: MeterUsageSummary[];
  quotas: UsageQuota[];
  recent_events: UsageEvent[];
  trends: Record<string, number>;
}

export interface MeterUsageSummary {
  id: string;
  name: string;
  slug: string;
  unit_name: string;
  total_usage: number;
  event_count: number;
  is_billable: boolean;
  calculated_cost: number;
  quota_limit?: number;
  quota_used: number;
  quota_percent: number;
  quota_exceeded: boolean;
}

export interface BillingSummary {
  period_start: string;
  period_end: string;
  summaries: UsageSummary[];
  total_usage_amount: number;
  total_overage_amount: number;
  grand_total: number;
}

export interface UsageEventInput {
  event_id?: string;
  meter_slug: string;
  quantity?: number;
  timestamp?: string;
  source?: UsageEventSource;
  user_id?: string;
  properties?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export interface BatchIngestionResult {
  success_count: number;
  failed_count: number;
  errors: Array<{ event_id?: string; error: string }>;
}
