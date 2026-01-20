// Publisher types for AI Marketplace

export interface Publisher {
  id: string;
  publisher_name: string;
  publisher_slug: string;
  status: 'pending' | 'active' | 'suspended' | 'rejected';
  verification_status: 'unverified' | 'pending' | 'verified';
  total_templates: number;
  total_installations: number;
  average_rating: number | null;
  created_at: string;
  // Extended fields (when include_details: true)
  account_id?: string;
  description?: string;
  website_url?: string;
  support_email?: string;
  revenue_share_percentage?: number;
  lifetime_earnings_usd?: number;
  pending_payout_usd?: number;
  stripe_account_status?: 'not_connected' | 'pending' | 'active' | 'restricted';
  stripe_payout_enabled?: boolean;
  branding?: {
    logo_url?: string;
    banner_url?: string;
    primary_color?: string;
  };
}

export interface PublisherDashboardStats {
  publisher: Publisher;
  overview: {
    total_templates: number;
    active_templates: number;
    pending_templates: number;
    total_installations: number;
    active_installations: number;
    average_rating: number | null;
    total_reviews: number;
  };
  earnings: {
    lifetime_earnings: number;
    pending_payout: number;
    revenue_share: number;
  };
  recent_sales: Transaction[];
  top_templates: TemplateSummary[];
}

export interface PublisherAnalytics {
  period: {
    start: string;
    end: string;
  };
  summary: {
    total_revenue: number;
    publisher_revenue: number;
    platform_commission: number;
    total_installations: number;
    total_uninstallations: number;
    net_installations: number;
    total_executions: number;
    page_views: number;
    unique_visitors: number;
  };
  daily_metrics: DailyMetric[];
  template_breakdown: TemplatePerformanceData[];
}

export interface DailyMetric {
  date: string;
  revenue: number;
  installations: number;
  page_views: number;
}

export interface TemplatePerformanceData {
  id: string;
  name: string;
  revenue: number;
  installations: number;
  executions: number;
  rating: number | null;
}

export interface PublisherEarnings {
  current: {
    lifetime_earnings: number;
    pending_payout: number;
    revenue_share_percentage: number;
    payout_enabled: boolean;
  };
  history: EarningsSnapshot[];
  recent_transactions: Transaction[];
}

export interface EarningsSnapshot {
  date: string;
  gross_earnings: number;
  net_earnings: number;
  pending_payout: number;
  paid_out: number;
  total_sales: number;
}

export interface Transaction {
  id: string;
  transaction_type: 'purchase' | 'refund' | 'payout';
  status: 'pending' | 'completed' | 'failed';
  gross_amount: number;
  publisher_amount: number;
  commission_amount: number;
  template_name: string | null;
  created_at: string;
}

export interface TemplateSummary {
  id: string;
  name: string;
  slug: string;
  status: string;
  pricing_type: 'free' | 'paid' | 'subscription';
  price_usd: number | null;
  installation_count: number;
  active_installations: number;
  average_rating: number | null;
  review_count: number;
  is_featured: boolean;
  is_verified: boolean;
  created_at: string;
}

export interface PayoutRequest {
  amount: number;
}

export interface StripeSetupRequest {
  return_url: string;
  refresh_url: string;
}

export interface StripeSetupResponse {
  onboarding_url: string;
}

export interface StripeStatusResponse {
  status: string;
  onboarding_completed: boolean;
  payout_enabled: boolean;
}

export interface PaginationMeta {
  pagination: {
    current_page: number;
    per_page: number;
    total_pages: number;
    total_count: number;
  };
}
