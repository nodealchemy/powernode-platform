// Core marketplace types

export interface App {
  id: string;
  name: string;
  slug: string;
  description: string;
  short_description: string;
  category: string;
  icon?: string;
  status: AppStatus;
  version: string;
  tags: string[];
  created_at: string;
  updated_at: string;
  published_at?: string;
  homepage_url?: string;
  documentation_url?: string;
  support_url?: string;
  repository_url?: string;
  license?: string;
  privacy_policy_url?: string;
  terms_of_service_url?: string;
  configuration: Record<string, any>;
  metadata: Record<string, any>;
  
  // Detailed view fields
  plans_count?: number;
  features_count?: number;
  subscriptions_count?: number;
  average_rating?: number;
  total_reviews?: number;
  total_revenue?: number;
  plans?: AppPlan[];
  features?: AppFeature[];
}

export type AppStatus = 'draft' | 'under_review' | 'published' | 'inactive';

export interface AppPlan {
  id: string;
  name: string;
  slug: string;
  description: string;
  price_cents: number;
  billing_interval: BillingInterval;
  is_active: boolean;
  sort_order: number;
  created_at: string;
  updated_at: string;
  trial_period_days?: number;
  setup_fee_cents?: number;
  formatted_price: string;
  is_free: boolean;
  features_count: number;
  permissions_count: number;
  
  // Detailed view fields
  features?: string[];
  permissions?: string[];
  limits?: Record<string, number>;
  metadata?: Record<string, any>;
  max_subscribers?: number;
  is_featured?: boolean;
  subscription_count?: number;
  active_subscriptions?: number;
  total_revenue?: number;
  monthly_revenue?: number;
  churn_rate?: number;
  upgrade_rate?: number;
  downgrade_rate?: number;
  feature_comparison?: Record<string, any>;
}

export type BillingInterval = 'monthly' | 'yearly' | 'one_time';

export interface AppFeature {
  id: string;
  name: string;
  slug: string;
  feature_type: FeatureType;
  description?: string;
  default_enabled: boolean;
  dependencies: string[];
  created_at: string;
  updated_at: string;
  has_dependencies: boolean;
  usage_count: number;
  
  // Detailed view fields
  configuration?: Record<string, any>;
  dependency_features?: FeatureSummary[];
  dependent_features?: FeatureSummary[];
  used_in_plans?: PlanSummary[];
  active_usage_count?: number;
  subscriber_count?: number;
  validation_errors?: string[];
  
  // Feature-type specific fields
  quota_limit?: number;
  quota_period?: string;
  quota_reset_day?: number;
  required_permission?: string;
  integration_provider?: string;
  integration_config?: Record<string, any>;
  api_endpoints?: string[];
  api_methods?: string[];
  ui_component_name?: string;
  ui_component_props?: Record<string, any>;
}

export type FeatureType = 'toggle' | 'quota' | 'permission' | 'integration' | 'api_access' | 'ui_component';

export interface FeatureSummary {
  id: string;
  name: string;
  slug: string;
}

export interface PlanSummary {
  id: string;
  name: string;
  is_active: boolean;
}

export interface MarketplaceListing {
  id: string;
  title: string;
  short_description: string;
  category: string;
  tags: string[];
  review_status: ReviewStatus;
  featured: boolean;
  published_at?: string;
  primary_screenshot?: string;
  created_at: string;
  updated_at: string;
  app: AppSummary;
  
  // Detailed view fields
  long_description?: string;
  documentation_url?: string;
  support_url?: string;
  homepage_url?: string;
  screenshots?: Screenshot[];
  screenshot_urls?: string[];
  formatted_tags?: string[];
  tag_list?: string;
  review_notes?: string;
  view_count?: number;
  subscription_count?: number;
  conversion_rate?: number;
  average_rating?: number;
  review_count?: number;
  similar_listings?: ListingSummary[];
  competing_listings?: ListingSummary[];
}

export type ReviewStatus = 'pending' | 'approved' | 'rejected';

export interface AppSummary {
  id: string;
  name: string;
  slug: string;
  status: AppStatus;
  app_plans?: AppPlan[];
}

export interface ListingSummary {
  id: string;
  title: string;
  category?: string;
  tags?: string[];
}

export interface Screenshot {
  url: string;
  caption?: string;
  order: number;
}

export interface MarketplaceCategory {
  slug: string;
  name: string;
  description?: string;
  icon?: string;
  apps_count: number;
}

export interface AppSubscription {
  id: string;
  status: SubscriptionStatus;
  subscribed_at: string;
  next_billing_at?: string;
  cancelled_at?: string;
  app: AppSummary;
  app_plan: AppPlan;
  configuration: Record<string, any>;
  usage_metrics: Record<string, any>;
  
  // Usage and analytics
  subscription_age_in_days?: number;
  total_amount_paid?: number;
  remaining_quota?: Record<string, number>;
  quota_percentage_used?: Record<string, number>;
  enabled_features?: AppFeature[];
}

export type SubscriptionStatus = 'active' | 'paused' | 'cancelled' | 'expired';

export interface AppReview {
  id: string;
  rating: number;
  title?: string;
  content?: string;
  helpful_count: number;
  created_at: string;
  updated_at: string;
  app: AppSummary;
  reviewer_name: string;
  
  // Display helpers
  star_display: string;
  display_title: string;
  formatted_date: string;
  time_ago: string;
  content_summary: string;
  word_count: number;
  
  // Verification
  verified_purchase: boolean;
  long_term_user: boolean;
  
  // Moderation
  flagged_for_review?: boolean;
  flag_reason?: string;
  removed?: boolean;
  removal_reason?: string;
  reviewed_at?: string;
}

// API Response types
export interface ApiResponse<T> {
  success: boolean;
  data: T;
  error?: string;
  details?: string[];
  message?: string;
}

export interface PaginatedResponse<T> {
  success: boolean;
  data: T[];
  pagination: {
    current_page: number;
    total_pages: number;
    total_count: number;
    per_page: number;
  };
}

// Form types
export interface AppFormData {
  name: string;
  slug?: string;
  description: string;
  short_description: string;
  category: string;
  icon?: string;
  homepage_url?: string;
  documentation_url?: string;
  support_url?: string;
  repository_url?: string;
  license?: string;
  privacy_policy_url?: string;
  terms_of_service_url?: string;
  tags: string[];
  configuration?: Record<string, any>;
  metadata?: Record<string, any>;
}

export interface AppPlanFormData {
  name: string;
  slug?: string;
  description: string;
  price_cents: number;
  billing_interval: BillingInterval;
  is_active: boolean;
  trial_period_days?: number;
  setup_fee_cents?: number;
  max_subscribers?: number;
  is_featured?: boolean;
  features: string[];
  permissions: string[];
  limits: Record<string, number>;
  metadata?: Record<string, any>;
}

export interface AppFeatureFormData {
  name: string;
  slug?: string;
  feature_type: FeatureType;
  description?: string;
  default_enabled: boolean;
  dependencies: string[];
  configuration: Record<string, any>;
}

export interface MarketplaceListingFormData {
  title: string;
  short_description: string;
  long_description?: string;
  category: string;
  documentation_url?: string;
  support_url?: string;
  homepage_url?: string;
  tags: string[];
  screenshots: Screenshot[];
}

export interface AppReviewFormData {
  rating: number;
  title?: string;
  content?: string;
}

// Filter and search types
export interface AppFilters {
  status?: AppStatus;
  search?: string;
  sort?: 'name' | 'created_at' | 'updated_at';
  page?: number;
  per_page?: number;
}

export interface MarketplaceFilters {
  status?: ReviewStatus;
  featured?: boolean;
  category?: string;
  tags?: string;
  search?: string;
  sort?: 'title' | 'category' | 'recent' | 'popular';
  page?: number;
  per_page?: number;
}

export interface AppPlanFilters {
  active?: boolean;
  search?: string;
  sort?: 'name' | 'price' | 'created_at';
}

export interface AppFeatureFilters {
  type?: FeatureType;
  default_enabled?: boolean;
  search?: string;
  sort?: 'name' | 'type' | 'created_at';
}

// Analytics types
export interface AppAnalytics {
  subscription_count: number;
  active_subscriptions: number;
  total_revenue: number;
  monthly_revenue: number;
  average_rating: number;
  total_reviews: number;
  download_count: number;
  recent_activity: Record<string, any>;
}

export interface PlanAnalytics {
  total_plans: number;
  active_plans: number;
  inactive_plans: number;
  subscription_distribution: Record<string, number>;
  revenue_by_plan: Record<string, number>;
  most_popular_plan?: string;
  average_plan_price: number;
}

// API Endpoints and Webhooks Types
export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD' | 'OPTIONS';
export type WebhookMethod = 'POST' | 'PUT' | 'PATCH';
export type DeliveryStatus = 'pending' | 'delivered' | 'failed' | 'cancelled';

export interface AppEndpoint {
  id: string;
  name: string;
  slug: string;
  description?: string;
  http_method: HttpMethod;
  path: string;
  full_path: string;
  request_schema?: any;
  response_schema?: any;
  headers: Record<string, any>;
  parameters: Record<string, any>;
  authentication: Record<string, any>;
  rate_limits: Record<string, any>;
  requires_auth: boolean;
  is_public: boolean;
  is_active: boolean;
  version: string;
  metadata: Record<string, any>;
  created_at: string;
  updated_at: string;
  analytics?: AppEndpointAnalytics;
}

export interface AppEndpointAnalytics {
  total_calls: number;
  calls_last_24h: number;
  average_response_time: number;
  success_rate: number;
  error_rate: number;
}

export interface AppEndpointCall {
  id: string;
  app_endpoint_id: string;
  account_id?: string;
  request_id: string;
  status_code: number;
  response_time_ms: number;
  request_size_bytes?: number;
  response_size_bytes?: number;
  user_agent?: string;
  ip_address?: string;
  request_headers: Record<string, any>;
  response_headers: Record<string, any>;
  error_message?: string;
  called_at: string;
}

export interface AppWebhook {
  id: string;
  name: string;
  slug: string;
  description?: string;
  event_type: string;
  url: string;
  http_method: WebhookMethod;
  headers: Record<string, any>;
  payload_template: Record<string, any>;
  authentication: Record<string, any>;
  retry_config: Record<string, any>;
  is_active: boolean;
  secret_token: string;
  timeout_seconds: number;
  max_retries: number;
  content_type: string;
  metadata: Record<string, any>;
  created_at: string;
  updated_at: string;
  analytics?: AppWebhookAnalytics;
}

export interface AppWebhookAnalytics {
  total_deliveries: number;
  deliveries_last_24h: number;
  success_rate: number;
  failure_rate: number;
  average_response_time: number;
  pending_deliveries: number;
  failed_deliveries: number;
}

export interface AppWebhookDelivery {
  id: string;
  delivery_id: string;
  event_id: string;
  status: DeliveryStatus;
  status_code?: number;
  response_time_ms?: number;
  attempt_number: number;
  error_message?: string;
  delivered_at?: string;
  next_retry_at?: string;
  created_at: string;
  updated_at: string;
}

// Form data interfaces
export interface AppEndpointFormData {
  name: string;
  slug?: string;
  description?: string;
  http_method: HttpMethod;
  path: string;
  request_schema?: string;
  response_schema?: string;
  headers?: Record<string, any>;
  parameters?: Record<string, any>;
  authentication?: Record<string, any>;
  rate_limits?: Record<string, any>;
  requires_auth: boolean;
  is_public: boolean;
  is_active: boolean;
  version: string;
  metadata?: Record<string, any>;
}

export interface AppWebhookFormData {
  name: string;
  slug?: string;
  description?: string;
  event_type: string;
  url: string;
  http_method: WebhookMethod;
  headers?: Record<string, any>;
  payload_template?: Record<string, any>;
  authentication?: Record<string, any>;
  retry_config?: Record<string, any>;
  is_active: boolean;
  timeout_seconds: number;
  max_retries: number;
  content_type: string;
  metadata?: Record<string, any>;
}

// Filter interfaces
export interface AppEndpointFilters {
  search?: string;
  method?: HttpMethod;
  active?: boolean;
  version?: string;
  page?: number;
  per_page?: number;
}

export interface AppWebhookFilters {
  search?: string;
  event_type?: string;
  active?: boolean;
  page?: number;
  per_page?: number;
}