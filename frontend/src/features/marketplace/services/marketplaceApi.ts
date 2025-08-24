import { api } from '@/shared/services/api';
import {
  App,
  AppPlan,
  AppFeature,
  MarketplaceListing,
  AppSubscription,
  AppReview,
  MarketplaceCategory,
  AppFormData,
  AppPlanFormData,
  AppFeatureFormData,
  MarketplaceListingFormData,
  AppReviewFormData,
  AppFilters,
  MarketplaceFilters,
  AppPlanFilters,
  AppFeatureFilters,
  ApiResponse,
  PaginatedResponse,
  AppAnalytics,
  PlanAnalytics
} from '../types';

// Apps API
export const appsApi = {
  async getApps(filters: AppFilters = {}): Promise<PaginatedResponse<App>> {
    const params = new URLSearchParams();
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined) params.append(key, value.toString());
    });
    
    const response = await api.get(`/apps?${params}`);
    return response.data;
  },

  async getApp(id: string): Promise<ApiResponse<App>> {
    const response = await api.get(`/apps/${id}`);
    return response.data;
  },

  async createApp(data: AppFormData): Promise<ApiResponse<App>> {
    const response = await api.post('/apps', { app: data });
    return response.data;
  },

  async updateApp(id: string, data: Partial<AppFormData>): Promise<ApiResponse<App>> {
    const response = await api.put(`/apps/${id}`, { app: data });
    return response.data;
  },

  async deleteApp(id: string): Promise<ApiResponse<void>> {
    const response = await api.delete(`/apps/${id}`);
    return response.data;
  },

  async publishApp(id: string): Promise<ApiResponse<App>> {
    const response = await api.post(`/apps/${id}/publish`);
    return response.data;
  },

  async unpublishApp(id: string): Promise<ApiResponse<App>> {
    const response = await api.post(`/apps/${id}/unpublish`);
    return response.data;
  },

  async submitForReview(id: string): Promise<ApiResponse<App>> {
    const response = await api.post(`/apps/${id}/submit_for_review`);
    return response.data;
  },

  async getAppAnalytics(id: string): Promise<ApiResponse<AppAnalytics>> {
    const response = await api.get(`/apps/${id}/analytics`);
    return response.data;
  }
};

// App Plans API
export const appPlansApi = {
  async getAppPlans(appId: string, filters: AppPlanFilters = {}): Promise<ApiResponse<AppPlan[]>> {
    const params = new URLSearchParams();
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined) params.append(key, value.toString());
    });
    
    const response = await api.get(`/apps/${appId}/app_plans?${params}`);
    return response.data;
  },

  async getAppPlan(appId: string, planId: string): Promise<ApiResponse<AppPlan>> {
    const response = await api.get(`/apps/${appId}/app_plans/${planId}`);
    return response.data;
  },

  async createAppPlan(appId: string, data: AppPlanFormData): Promise<ApiResponse<AppPlan>> {
    const response = await api.post(`/apps/${appId}/app_plans`, { app_plan: data });
    return response.data;
  },

  async updateAppPlan(appId: string, planId: string, data: Partial<AppPlanFormData>): Promise<ApiResponse<AppPlan>> {
    const response = await api.put(`/apps/${appId}/app_plans/${planId}`, { app_plan: data });
    return response.data;
  },

  async deleteAppPlan(appId: string, planId: string): Promise<ApiResponse<void>> {
    const response = await api.delete(`/apps/${appId}/app_plans/${planId}`);
    return response.data;
  },

  async activateAppPlan(appId: string, planId: string): Promise<ApiResponse<AppPlan>> {
    const response = await api.post(`/apps/${appId}/app_plans/${planId}/activate`);
    return response.data;
  },

  async deactivateAppPlan(appId: string, planId: string): Promise<ApiResponse<AppPlan>> {
    const response = await api.post(`/apps/${appId}/app_plans/${planId}/deactivate`);
    return response.data;
  },

  async reorderAppPlans(appId: string, planIds: string[]): Promise<ApiResponse<void>> {
    const response = await api.post(`/apps/${appId}/app_plans/reorder`, { plan_ids: planIds });
    return response.data;
  },

  async compareAppPlans(appId: string, planIds: string[]): Promise<ApiResponse<any>> {
    const response = await api.get(`/apps/${appId}/app_plans/compare?plan_ids=${planIds.join(',')}`);
    return response.data;
  },

  async getAppPlanAnalytics(appId: string): Promise<ApiResponse<PlanAnalytics>> {
    const response = await api.get(`/apps/${appId}/app_plans/analytics`);
    return response.data;
  }
};

// App Features API
export const appFeaturesApi = {
  async getAppFeatures(appId: string, filters: AppFeatureFilters = {}): Promise<ApiResponse<AppFeature[]>> {
    const params = new URLSearchParams();
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined) params.append(key, value.toString());
    });
    
    const response = await api.get(`/apps/${appId}/app_features?${params}`);
    return response.data;
  },

  async getAppFeature(appId: string, featureId: string): Promise<ApiResponse<AppFeature>> {
    const response = await api.get(`/apps/${appId}/app_features/${featureId}`);
    return response.data;
  },

  async createAppFeature(appId: string, data: AppFeatureFormData): Promise<ApiResponse<AppFeature>> {
    const response = await api.post(`/apps/${appId}/app_features`, { app_feature: data });
    return response.data;
  },

  async updateAppFeature(appId: string, featureId: string, data: Partial<AppFeatureFormData>): Promise<ApiResponse<AppFeature>> {
    const response = await api.put(`/apps/${appId}/app_features/${featureId}`, { app_feature: data });
    return response.data;
  },

  async deleteAppFeature(appId: string, featureId: string): Promise<ApiResponse<void>> {
    const response = await api.delete(`/apps/${appId}/app_features/${featureId}`);
    return response.data;
  },

  async enableByDefault(appId: string, featureId: string): Promise<ApiResponse<AppFeature>> {
    const response = await api.post(`/apps/${appId}/app_features/${featureId}/enable_by_default`);
    return response.data;
  },

  async disableByDefault(appId: string, featureId: string): Promise<ApiResponse<AppFeature>> {
    const response = await api.post(`/apps/${appId}/app_features/${featureId}/disable_by_default`);
    return response.data;
  },

  async duplicateAppFeature(appId: string, featureId: string, name?: string): Promise<ApiResponse<AppFeature>> {
    const response = await api.post(`/apps/${appId}/app_features/${featureId}/duplicate`, { name });
    return response.data;
  },

  async getFeatureTypes(): Promise<ApiResponse<any>> {
    const response = await api.get('/apps/0/app_features/types'); // Using dummy app ID for types endpoint
    return response.data;
  },

  async getDependencies(appId: string, excludeId?: string): Promise<ApiResponse<any>> {
    const params = excludeId ? `?exclude_id=${excludeId}` : '';
    const response = await api.get(`/apps/${appId}/app_features/dependencies${params}`);
    return response.data;
  },

  async validateDependencies(appId: string, featureId: string, dependencies: string[]): Promise<ApiResponse<any>> {
    const response = await api.post(`/apps/${appId}/app_features/validate_dependencies`, {
      feature_id: featureId,
      dependencies
    });
    return response.data;
  },

  async getUsageReport(appId: string): Promise<ApiResponse<any>> {
    const response = await api.get(`/apps/${appId}/app_features/usage_report`);
    return response.data;
  }
};

// Marketplace Listings API
export const marketplaceListingsApi = {
  async getMarketplaceListings(filters: MarketplaceFilters = {}): Promise<PaginatedResponse<MarketplaceListing>> {
    const params = new URLSearchParams();
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined) params.append(key, value.toString());
    });
    
    const response = await api.get(`/marketplace_listings?${params}`);
    return response.data;
  },

  async getMarketplaceListing(id: string): Promise<ApiResponse<MarketplaceListing>> {
    const response = await api.get(`/marketplace_listings/${id}`);
    return response.data;
  },

  async createMarketplaceListing(appId: string, data: MarketplaceListingFormData): Promise<ApiResponse<MarketplaceListing>> {
    const response = await api.post(`/apps/${appId}/marketplace_listing`, { marketplace_listing: data });
    return response.data;
  },

  async updateMarketplaceListing(appId: string, data: Partial<MarketplaceListingFormData>): Promise<ApiResponse<MarketplaceListing>> {
    const response = await api.put(`/apps/${appId}/marketplace_listing`, { marketplace_listing: data });
    return response.data;
  },

  async deleteMarketplaceListing(appId: string): Promise<ApiResponse<void>> {
    const response = await api.delete(`/apps/${appId}/marketplace_listing`);
    return response.data;
  },

  async submitForReview(appId: string): Promise<ApiResponse<MarketplaceListing>> {
    const response = await api.post(`/apps/${appId}/marketplace_listing/submit`);
    return response.data;
  },

  async approveListing(appId: string, notes?: string): Promise<ApiResponse<MarketplaceListing>> {
    const response = await api.post(`/apps/${appId}/marketplace_listing/approve`, { notes });
    return response.data;
  },

  async rejectListing(appId: string, notes: string): Promise<ApiResponse<MarketplaceListing>> {
    const response = await api.post(`/apps/${appId}/marketplace_listing/reject`, { notes });
    return response.data;
  },

  async featureListing(appId: string): Promise<ApiResponse<MarketplaceListing>> {
    const response = await api.post(`/apps/${appId}/marketplace_listing/feature`);
    return response.data;
  },

  async unfeatureListing(appId: string): Promise<ApiResponse<MarketplaceListing>> {
    const response = await api.post(`/apps/${appId}/marketplace_listing/unfeature`);
    return response.data;
  },

  async getListingAnalytics(appId: string): Promise<ApiResponse<any>> {
    const response = await api.get(`/apps/${appId}/marketplace_listing/analytics`);
    return response.data;
  },

  async addScreenshot(appId: string, url: string, caption?: string): Promise<ApiResponse<any>> {
    const response = await api.post(`/apps/${appId}/marketplace_listing/screenshots`, { url, caption });
    return response.data;
  },

  async removeScreenshot(appId: string, index: number): Promise<ApiResponse<any>> {
    const response = await api.delete(`/apps/${appId}/marketplace_listing/screenshots`, { data: { index } });
    return response.data;
  },

  async reorderScreenshots(appId: string, order: number[]): Promise<ApiResponse<any>> {
    const response = await api.patch(`/apps/${appId}/marketplace_listing/screenshots`, { order });
    return response.data;
  },

  async getCategories(): Promise<ApiResponse<MarketplaceCategory[]>> {
    const response = await api.get('/marketplace_listings/categories');
    return response.data;
  }
};

// App Subscriptions API
export const appSubscriptionsApi = {
  async getAppSubscriptions(): Promise<ApiResponse<AppSubscription[]>> {
    const response = await api.get('/app_subscriptions');
    return response.data;
  },

  async getAppSubscription(id: string): Promise<ApiResponse<AppSubscription>> {
    const response = await api.get(`/app_subscriptions/${id}`);
    return response.data;
  },

  async createAppSubscription(data: { app_id: string; app_plan_id: string }): Promise<ApiResponse<AppSubscription>> {
    const response = await api.post('/app_subscriptions', data);
    return response.data;
  },

  async updateAppSubscription(id: string, data: any): Promise<ApiResponse<AppSubscription>> {
    const response = await api.put(`/app_subscriptions/${id}`, data);
    return response.data;
  },

  async cancelAppSubscription(id: string): Promise<ApiResponse<AppSubscription>> {
    const response = await api.post(`/app_subscriptions/${id}/cancel`);
    return response.data;
  },

  async pauseAppSubscription(id: string): Promise<ApiResponse<AppSubscription>> {
    const response = await api.post(`/app_subscriptions/${id}/pause`);
    return response.data;
  },

  async resumeAppSubscription(id: string): Promise<ApiResponse<AppSubscription>> {
    const response = await api.post(`/app_subscriptions/${id}/resume`);
    return response.data;
  },

  async upgradePlan(id: string, planId: string): Promise<ApiResponse<AppSubscription>> {
    const response = await api.post(`/app_subscriptions/${id}/upgrade_plan`, { plan_id: planId });
    return response.data;
  },

  async downgradePlan(id: string, planId: string): Promise<ApiResponse<AppSubscription>> {
    const response = await api.post(`/app_subscriptions/${id}/downgrade_plan`, { plan_id: planId });
    return response.data;
  },

  async getUsage(id: string): Promise<ApiResponse<any>> {
    const response = await api.get(`/app_subscriptions/${id}/usage`);
    return response.data;
  },

  async getSubscriptionAnalytics(id: string): Promise<ApiResponse<any>> {
    const response = await api.get(`/app_subscriptions/${id}/analytics`);
    return response.data;
  },

  async getActiveSubscriptions(): Promise<ApiResponse<AppSubscription[]>> {
    const response = await api.get('/app_subscriptions/active');
    return response.data;
  },

  async getCancelledSubscriptions(): Promise<ApiResponse<AppSubscription[]>> {
    const response = await api.get('/app_subscriptions/cancelled');
    return response.data;
  },

  async getExpiredSubscriptions(): Promise<ApiResponse<AppSubscription[]>> {
    const response = await api.get('/app_subscriptions/expired');
    return response.data;
  }
};

// App Reviews API
export const appReviewsApi = {
  async getAppReviews(): Promise<ApiResponse<AppReview[]>> {
    const response = await api.get('/app_reviews');
    return response.data;
  },

  async getAppReview(id: string): Promise<ApiResponse<AppReview>> {
    const response = await api.get(`/app_reviews/${id}`);
    return response.data;
  },

  async createAppReview(data: AppReviewFormData & { app_id: string }): Promise<ApiResponse<AppReview>> {
    const response = await api.post('/app_reviews', { app_review: data });
    return response.data;
  },

  async updateAppReview(id: string, data: Partial<AppReviewFormData>): Promise<ApiResponse<AppReview>> {
    const response = await api.put(`/app_reviews/${id}`, { app_review: data });
    return response.data;
  },

  async deleteAppReview(id: string): Promise<ApiResponse<void>> {
    const response = await api.delete(`/app_reviews/${id}`);
    return response.data;
  },

  async markHelpful(id: string): Promise<ApiResponse<AppReview>> {
    const response = await api.post(`/app_reviews/${id}/mark_helpful`);
    return response.data;
  },

  async markUnhelpful(id: string): Promise<ApiResponse<AppReview>> {
    const response = await api.post(`/app_reviews/${id}/mark_unhelpful`);
    return response.data;
  },

  async flagForReview(id: string, reason?: string): Promise<ApiResponse<AppReview>> {
    const response = await api.post(`/app_reviews/${id}/flag_for_review`, { reason });
    return response.data;
  },

  async approveAfterReview(id: string): Promise<ApiResponse<AppReview>> {
    const response = await api.post(`/app_reviews/${id}/approve_after_review`);
    return response.data;
  },

  async removeAfterReview(id: string, reason?: string): Promise<ApiResponse<AppReview>> {
    const response = await api.post(`/app_reviews/${id}/remove_after_review`, { reason });
    return response.data;
  },

  async getReviewsByApp(appId: string): Promise<ApiResponse<AppReview[]>> {
    const response = await api.get(`/app_reviews/by_app?app_id=${appId}`);
    return response.data;
  },

  async getReviewsByRating(rating: number): Promise<ApiResponse<AppReview[]>> {
    const response = await api.get(`/app_reviews/by_rating?rating=${rating}`);
    return response.data;
  },

  async getSentimentAnalysis(): Promise<ApiResponse<any>> {
    const response = await api.get('/app_reviews/sentiment_analysis');
    return response.data;
  },

  async getModerationQueue(): Promise<ApiResponse<AppReview[]>> {
    const response = await api.get('/app_reviews/moderation_queue');
    return response.data;
  }
};