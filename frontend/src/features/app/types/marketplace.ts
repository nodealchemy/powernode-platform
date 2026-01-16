/**
 * Marketplace Type System
 *
 * Core types for the feature template marketplace.
 * Templates are aligned with actual application features:
 * - workflow_template: AI Workflow templates
 * - pipeline_template: CI/CD Pipeline templates
 * - integration_template: Integration templates
 * - prompt_template: Prompt templates
 */

// Feature-aligned template types
export type MarketplaceItemType =
  | 'workflow_template'    // AI Workflows
  | 'pipeline_template'    // CI/CD Pipelines
  | 'integration_template' // Integrations
  | 'prompt_template';     // Prompts

// Publisher information
export interface Publisher {
  id: string;
  display_name: string;
  bio?: string;
  website?: string;
  logo_url?: string;
  verified: boolean;
}

export interface MarketplaceItem {
  id: string;
  type: MarketplaceItemType;
  name: string;
  slug: string;
  description: string;
  category: string;
  tags: string[];
  icon?: string;
  version: string;
  rating: number;
  rating_count: number;
  install_count: number;
  is_verified: boolean;
  is_featured: boolean;
  status: 'published' | 'draft' | 'archived';
  created_at: string;
  published_at?: string;

  // Publisher information
  publisher?: Publisher;
  account_id?: string;

  // Marketplace publishing status
  marketplace_status?: 'pending' | 'approved' | 'rejected';
  is_marketplace_published?: boolean;

  // Type-specific fields
  capabilities?: string[];
  difficulty_level?: 'beginner' | 'intermediate' | 'advanced' | 'expert';
  node_count?: number;
  step_count?: number;
  integration_type?: string;

  // Template-specific content (for detail view)
  template_definition?: Record<string, unknown>;
  default_variables?: Record<string, unknown>;

  // Subscription info (when authenticated)
  subscription?: MarketplaceSubscriptionInfo;
}

export interface MarketplaceSubscriptionInfo {
  id: string;
  status: 'active' | 'paused' | 'cancelled' | 'expired';
  tier: 'free' | 'standard' | 'premium' | 'enterprise';
  subscribed_at: string;
}

export interface MarketplaceSubscription {
  id: string;
  item_id: string;
  item_type: MarketplaceItemType;
  item_name: string;
  item_slug: string;
  item_icon?: string;
  status: 'active' | 'paused' | 'cancelled' | 'expired';
  tier: 'free' | 'standard' | 'premium' | 'enterprise';
  subscribed_at: string;
  configuration: Record<string, unknown>;
  usage_metrics?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  next_billing_at?: string;
  days_until_billing?: number;
  subscription_age_days?: number;
  item?: MarketplaceItem;
}

export interface MarketplaceReview {
  id: string;
  rating: number;
  title?: string;
  content?: string;
  verified_purchase: boolean;
  helpful_count: number;
  moderation_status: 'pending' | 'approved' | 'rejected' | 'flagged';
  created_at: string;
  updated_at: string;
  author: {
    id: string;
    name: string;
    avatar?: string;
  };
  reviewable?: {
    id: string;
    type: string;
    name: string;
  };
}

export interface MarketplaceCategory {
  name: string;
  count: number;
  types: MarketplaceItemType[];
}

export interface MarketplaceFilters {
  types?: MarketplaceItemType[];
  search?: string;
  category?: string;
  verified?: boolean;
}

export interface MarketplaceMeta {
  total_count: number;
  current_page: number;
  per_page: number;
  total_pages: number;
  filters?: MarketplaceFilters;
}

export interface SubscriptionsMeta {
  total_count: number;
  current_page: number;
  per_page: number;
  total_pages: number;
  counts_by_type: {
    workflow_template: number;
    pipeline_template: number;
    integration_template: number;
    prompt_template: number;
  };
  counts_by_status: {
    active: number;
    paused: number;
    cancelled: number;
  };
}

export interface ReviewsMeta {
  total_count: number;
  current_page: number;
  per_page: number;
  total_pages: number;
  rating_distribution: Record<number, number>;
}

// API Request Types
export interface SubscribeRequest {
  tier?: 'free' | 'standard' | 'premium' | 'enterprise';
  plan_id?: string;
  configuration?: Record<string, unknown>;
  create_workflow?: boolean;
  workflow_name?: string;
}

export interface CreateReviewRequest {
  item_type: MarketplaceItemType;
  item_id: string;
  rating: number;
  title?: string;
  content?: string;
}

export interface UpdateReviewRequest {
  rating?: number;
  title?: string;
  content?: string;
}

// API Response Types
export interface MarketplaceListResponse {
  success: boolean;
  data: MarketplaceItem[];
  meta: MarketplaceMeta;
}

export interface MarketplaceItemResponse {
  success: boolean;
  data: MarketplaceItem;
}

export interface SubscriptionsListResponse {
  success: boolean;
  data: MarketplaceSubscription[];
  meta: SubscriptionsMeta;
}

export interface SubscriptionResponse {
  success: boolean;
  data: MarketplaceSubscription;
}

export interface ReviewsListResponse {
  success: boolean;
  data: MarketplaceReview[];
  meta: ReviewsMeta;
}

export interface ReviewResponse {
  success: boolean;
  data: MarketplaceReview;
}

export interface CategoriesResponse {
  success: boolean;
  data: MarketplaceCategory[];
}

// ============================================
// Helper Functions
// ============================================

/**
 * Get display name for marketplace item type
 */
export function getTypeDisplayName(type: MarketplaceItemType): string {
  const names: Record<MarketplaceItemType, string> = {
    workflow_template: 'Workflow',
    pipeline_template: 'Pipeline',
    integration_template: 'Integration',
    prompt_template: 'Prompt',
  };
  return names[type] || type;
}

/**
 * Get description for marketplace item type
 */
export function getTypeDescription(type: MarketplaceItemType): string {
  const descriptions: Record<MarketplaceItemType, string> = {
    workflow_template: 'AI Workflow automation templates',
    pipeline_template: 'CI/CD Pipeline templates',
    integration_template: 'Third-party integration templates',
    prompt_template: 'AI prompt templates',
  };
  return descriptions[type] || '';
}

/**
 * Get badge color class for marketplace item type
 */
export function getTypeBadgeColor(type: MarketplaceItemType): string {
  const colors: Record<MarketplaceItemType, string> = {
    workflow_template: 'bg-theme-info bg-opacity-10 text-theme-info',
    pipeline_template: 'bg-theme-success bg-opacity-10 text-theme-success',
    integration_template: 'bg-theme-primary bg-opacity-10 text-theme-primary',
    prompt_template: 'bg-theme-warning bg-opacity-10 text-theme-warning',
  };
  return colors[type] || 'bg-theme-surface text-theme-primary';
}

/**
 * Get icon name for marketplace item type
 */
export function getTypeIcon(type: MarketplaceItemType): string {
  const icons: Record<MarketplaceItemType, string> = {
    workflow_template: 'Workflow',
    pipeline_template: 'GitBranch',
    integration_template: 'Puzzle',
    prompt_template: 'MessageSquare',
  };
  return icons[type] || 'Package';
}

/**
 * All available marketplace item types
 */
export const ALL_MARKETPLACE_TYPES: MarketplaceItemType[] = [
  'workflow_template',
  'pipeline_template',
  'integration_template',
  'prompt_template',
];
