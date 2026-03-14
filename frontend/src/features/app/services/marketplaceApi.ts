/**
 * Marketplace API Service
 *
 * Frontend API service for marketplace endpoints.
 * Handles apps, plugins, templates, and integrations through a single interface.
 */

import { api } from '@/shared/services/api';
import type {
  MarketplaceItem,
  MarketplaceFilters,
  MarketplaceItemType,
  MarketplaceListResponse,
  MarketplaceItemResponse,
  MarketplaceSubscription,
  MarketplaceReview,
  SubscriptionsListResponse,
  SubscriptionResponse,
  ReviewsListResponse,
  ReviewResponse,
  CategoriesResponse,
  MarketplaceCategory,
  SubscribeRequest,
  CreateReviewRequest,
  UpdateReviewRequest
} from '../types/marketplace';

// Re-export types for convenience
export type {
  MarketplaceItem,
  MarketplaceFilters,
  MarketplaceItemType,
  MarketplaceSubscription,
  MarketplaceReview,
  MarketplaceCategory
};

class MarketplaceApi {
  // =====================
  // Items
  // =====================

  /**
   * Get marketplace items with optional filters
   */
  async getItems(filters?: MarketplaceFilters, page = 1, perPage = 20): Promise<MarketplaceListResponse> {
    const params = new URLSearchParams();

    if (filters?.types && filters.types.length > 0) {
      params.append('types', filters.types.join(','));
    }
    if (filters?.search) {
      params.append('search', filters.search);
    }
    if (filters?.category) {
      params.append('category', filters.category);
    }
    if (filters?.verified !== undefined) {
      params.append('verified', String(filters.verified));
    }
    params.append('page', String(page));
    params.append('per_page', String(perPage));

    const queryString = params.toString();
    const url = `/marketplace${queryString ? `?${queryString}` : ''}`;

    const response = await api.get(url);
    return response.data;
  }

  /**
   * Get featured marketplace items
   */
  async getFeatured(): Promise<{ success: boolean; data: MarketplaceItem[] }> {
    const response = await api.get('/marketplace/featured');
    return response.data;
  }

  /**
   * Get marketplace categories
   */
  async getCategories(): Promise<CategoriesResponse> {
    const response = await api.get('/marketplace/categories');
    return response.data;
  }

  /**
   * Get a single marketplace item by type and ID
   */
  async getItem(type: MarketplaceItemType, id: string): Promise<MarketplaceItemResponse> {
    const response = await api.get(`/marketplace/${type}/${id}`);
    return response.data;
  }

  /**
   * Subscribe to a marketplace item
   */
  async subscribe(type: MarketplaceItemType, id: string, options?: SubscribeRequest): Promise<SubscriptionResponse> {
    const response = await api.post(`/marketplace/${type}/${id}/subscribe`, options || {});
    return response.data;
  }

  /**
   * Unsubscribe from a marketplace item
   */
  async unsubscribe(type: MarketplaceItemType, id: string, reason?: string): Promise<{ success: boolean; data: { message: string } }> {
    const response = await api.delete(`/marketplace/${type}/${id}/unsubscribe`, {
      data: reason ? { reason } : undefined
    });
    return response.data;
  }

  // =====================
  // Subscriptions
  // =====================

  /**
   * Get all subscriptions for current account
   */
  async getSubscriptions(params?: {
    type?: MarketplaceItemType;
    status?: string;
    page?: number;
    per_page?: number;
  }): Promise<SubscriptionsListResponse> {
    const queryParams = new URLSearchParams();
    if (params?.type) queryParams.append('type', params.type);
    if (params?.status) queryParams.append('status', params.status);
    if (params?.page) queryParams.append('page', String(params.page));
    if (params?.per_page) queryParams.append('per_page', String(params.per_page));

    const queryString = queryParams.toString();
    const url = `/marketplace/subscriptions${queryString ? `?${queryString}` : ''}`;

    const response = await api.get(url);
    return response.data;
  }

  /**
   * Get a single subscription
   */
  async getSubscription(id: string): Promise<SubscriptionResponse> {
    const response = await api.get(`/marketplace/subscriptions/${id}`);
    return response.data;
  }

  /**
   * Update subscription configuration
   */
  async updateSubscription(id: string, configuration: Record<string, unknown>): Promise<SubscriptionResponse> {
    const response = await api.patch(`/marketplace/subscriptions/${id}`, { configuration });
    return response.data;
  }

  /**
   * Cancel a subscription
   */
  async cancelSubscription(id: string, reason?: string): Promise<{ success: boolean; data: { message: string } }> {
    const response = await api.delete(`/marketplace/subscriptions/${id}`, {
      data: reason ? { reason } : undefined
    });
    return response.data;
  }

  /**
   * Pause a subscription
   */
  async pauseSubscription(id: string, reason?: string): Promise<SubscriptionResponse> {
    const response = await api.post(`/marketplace/subscriptions/${id}/pause`, { reason });
    return response.data;
  }

  /**
   * Resume a subscription
   */
  async resumeSubscription(id: string): Promise<SubscriptionResponse> {
    const response = await api.post(`/marketplace/subscriptions/${id}/resume`);
    return response.data;
  }

  /**
   * Configure a subscription
   */
  async configureSubscription(id: string, configuration: Record<string, unknown>): Promise<SubscriptionResponse> {
    const response = await api.patch(`/marketplace/subscriptions/${id}/configure`, { configuration });
    return response.data;
  }

  /**
   * Upgrade subscription tier
   */
  async upgradeSubscriptionTier(id: string, tier: string): Promise<SubscriptionResponse> {
    const response = await api.post(`/marketplace/subscriptions/${id}/upgrade_tier`, { tier });
    return response.data;
  }

  /**
   * Get subscription usage
   */
  async getSubscriptionUsage(id: string): Promise<{
    success: boolean;
    data: {
      subscription_id: string;
      usage_metrics: Record<string, unknown>;
      usage_within_limits: boolean;
      subscription_age_days: number;
    };
  }> {
    const response = await api.get(`/marketplace/subscriptions/${id}/usage`);
    return response.data;
  }

  // =====================
  // Reviews
  // =====================

  /**
   * Get reviews for an item
   */
  async getReviews(params?: {
    item_type?: MarketplaceItemType;
    item_id?: string;
    rating?: number;
    verified?: boolean;
    sort?: 'recent' | 'helpful' | 'rating_high' | 'rating_low';
    page?: number;
    per_page?: number;
  }): Promise<ReviewsListResponse> {
    const queryParams = new URLSearchParams();
    if (params?.item_type) queryParams.append('item_type', params.item_type);
    if (params?.item_id) queryParams.append('item_id', params.item_id);
    if (params?.rating) queryParams.append('rating', String(params.rating));
    if (params?.verified) queryParams.append('verified', 'true');
    if (params?.sort) queryParams.append('sort', params.sort);
    if (params?.page) queryParams.append('page', String(params.page));
    if (params?.per_page) queryParams.append('per_page', String(params.per_page));

    const queryString = queryParams.toString();
    const url = `/marketplace/reviews${queryString ? `?${queryString}` : ''}`;

    const response = await api.get(url);
    return response.data;
  }

  /**
   * Get a single review
   */
  async getReview(id: string): Promise<ReviewResponse> {
    const response = await api.get(`/marketplace/reviews/${id}`);
    return response.data;
  }

  /**
   * Create a review
   */
  async createReview(data: CreateReviewRequest): Promise<ReviewResponse> {
    const response = await api.post('/marketplace/reviews', data);
    return response.data;
  }

  /**
   * Update a review
   */
  async updateReview(id: string, data: UpdateReviewRequest): Promise<ReviewResponse> {
    const response = await api.patch(`/marketplace/reviews/${id}`, data);
    return response.data;
  }

  /**
   * Delete a review
   */
  async deleteReview(id: string): Promise<{ success: boolean; data: { message: string } }> {
    const response = await api.delete(`/marketplace/reviews/${id}`);
    return response.data;
  }

  /**
   * Mark a review as helpful
   */
  async markReviewHelpful(id: string): Promise<{ success: boolean; data: { helpful_count: number } }> {
    const response = await api.post(`/marketplace/reviews/${id}/helpful`);
    return response.data;
  }

  /**
   * Flag a review for moderation
   */
  async flagReview(id: string): Promise<{ success: boolean; data: { message: string } }> {
    const response = await api.post(`/marketplace/reviews/${id}/flag`);
    return response.data;
  }

  // =====================
  // Template Publishing (Admin)
  // =====================

  /**
   * Get templates pending review (admin)
   */
  async getPendingTemplates(): Promise<{
    success: boolean;
    data: MarketplaceItem[];
    meta?: { total_count: number };
  }> {
    const response = await api.get('/marketplace/templates/pending_review');
    return response.data;
  }

  /**
   * Approve a template for marketplace (admin)
   */
  async approveTemplate(type: MarketplaceItemType, id: string): Promise<{
    success: boolean;
    data: MarketplaceItem;
    message: string;
  }> {
    const response = await api.post(`/marketplace/templates/${type}/${id}/approve`);
    return response.data;
  }

  /**
   * Reject a template from marketplace (admin)
   */
  async rejectTemplate(type: MarketplaceItemType, id: string, reason: string): Promise<{
    success: boolean;
    data: MarketplaceItem;
    message: string;
  }> {
    const response = await api.post(`/marketplace/templates/${type}/${id}/reject`, { reason });
    return response.data;
  }

  /**
   * Get user's own published templates
   */
  async getMyPublishedTemplates(): Promise<{
    success: boolean;
    data: MarketplaceItem[];
    meta?: {
      total_count: number;
      counts_by_type: Record<string, number>;
    };
  }> {
    const response = await api.get('/marketplace/templates/my_published');
    return response.data;
  }

  /**
   * Create template from workflow
   */
  async createTemplateFromWorkflow(workflowId: string, params: {
    name?: string;
    description?: string;
    category?: string;
    difficulty_level?: string;
    tags?: string[];
  }): Promise<{ success: boolean; data: MarketplaceItem; message: string }> {
    const response = await api.post(`/marketplace/templates/from_workflow/${workflowId}`, params);
    return response.data;
  }

  /**
   * Create template from pipeline
   */
  async createTemplateFromPipeline(pipelineId: string, params: {
    name?: string;
    description?: string;
    category?: string;
    difficulty_level?: string;
    tags?: string[];
  }): Promise<{ success: boolean; data: MarketplaceItem; message: string }> {
    const response = await api.post(`/marketplace/templates/from_pipeline/${pipelineId}`, params);
    return response.data;
  }

  /**
   * Submit template for marketplace review
   */
  async submitTemplate(type: MarketplaceItemType, id: string): Promise<{
    success: boolean;
    data: MarketplaceItem;
    message: string;
  }> {
    const response = await api.post(`/marketplace/templates/${type}/${id}/submit`);
    return response.data;
  }

  /**
   * Withdraw template from marketplace
   */
  async withdrawTemplate(type: MarketplaceItemType, id: string): Promise<{
    success: boolean;
    data: MarketplaceItem;
    message: string;
  }> {
    const response = await api.post(`/marketplace/templates/${type}/${id}/withdraw`);
    return response.data;
  }

  /**
   * Create instance from subscribed template
   */
  async createInstanceFromTemplate(type: MarketplaceItemType, id: string, params: {
    name?: string;
    description?: string;
    variables?: Record<string, unknown>;
    configuration?: Record<string, unknown>;
  }): Promise<{
    success: boolean;
    data: { id: string; name: string; type: string };
    message: string;
  }> {
    const response = await api.post(`/marketplace/templates/${type}/${id}/create_instance`, params);
    return response.data;
  }
}

export const marketplaceApi = new MarketplaceApi();
