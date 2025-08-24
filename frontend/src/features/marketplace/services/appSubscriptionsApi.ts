import { api } from '@/shared/services/api';

export interface AppSubscription {
  id: string;
  status: 'active' | 'paused' | 'cancelled' | 'expired';
  subscribed_at: string;
  next_billing_at: string | null;
  cancelled_at: string | null;
  created_at: string;
  updated_at: string;
  configuration: Record<string, any>;
  usage_metrics?: Record<string, any>;
  enabled_features?: Array<{
    slug: string;
    name: string;
    description: string;
  }>;
  limits?: Record<string, number>;
  permissions?: string[];
  usage_within_limits?: boolean;
  next_billing_amount?: string;
  days_until_billing?: number;
  subscription_age_days?: number;
  total_amount_paid?: number;
  app: {
    id: string;
    name: string;
    slug: string;
    status: string;
    icon?: string;
  };
  app_plan: {
    id: string;
    name: string;
    slug: string;
    price_cents: number;
    billing_interval: string;
    formatted_price: string;
  };
}

export interface SubscriptionUsage {
  current_period_usage: Record<string, any>;
  limits: Record<string, number>;
  quota_usage: Record<string, number>;
  remaining_quotas: Record<string, number>;
  billing_info: {
    next_billing_at: string | null;
    next_billing_amount: string;
    days_until_billing: number | null;
  };
}

export interface SubscriptionAnalytics {
  subscription_age_days: number;
  total_amount_paid: number;
  average_monthly_usage: Record<string, number>;
  usage_trends: Record<string, any>;
  feature_usage: Array<{
    slug: string;
    name: string;
    usage_count: number;
  }>;
  billing_history: Array<{
    date: string;
    amount: number;
    formatted_amount: string;
  }>;
  status_changes: Array<{
    status: string;
    date: string;
    reason?: string;
  }>;
}

export const appSubscriptionsApi = {
  async getSubscriptions(page = 1, perPage = 20, status?: string): Promise<{
    data: AppSubscription[];
    pagination: {
      current_page: number;
      total_pages: number;
      total_count: number;
      per_page: number;
    };
  }> {
    const params = new URLSearchParams({
      page: page.toString(),
      per_page: perPage.toString(),
    });
    
    if (status) {
      params.append('status', status);
    }
    
    const response = await api.get(`/app_subscriptions?${params.toString()}`);
    return response.data;
  },

  async getActiveSubscriptions(): Promise<AppSubscription[]> {
    const response = await api.get('/app_subscriptions/active');
    return response.data.data;
  },

  async getCancelledSubscriptions(): Promise<AppSubscription[]> {
    const response = await api.get('/app_subscriptions/cancelled');
    return response.data.data;
  },

  async getExpiredSubscriptions(): Promise<AppSubscription[]> {
    const response = await api.get('/app_subscriptions/expired');
    return response.data.data;
  },

  async getSubscription(id: string): Promise<AppSubscription> {
    const response = await api.get(`/app_subscriptions/${id}`);
    return response.data.data;
  },

  async createSubscription(appId: string, planId: string, configuration?: Record<string, any>): Promise<AppSubscription> {
    const response = await api.post('/app_subscriptions', {
      app_subscription: {
        configuration: configuration || {}
      },
      app_id: appId,
      app_plan_id: planId
    });
    return response.data.data;
  },

  async updateSubscription(id: string, configuration: Record<string, any>): Promise<AppSubscription> {
    const response = await api.put(`/app_subscriptions/${id}`, {
      app_subscription: {
        configuration
      }
    });
    return response.data.data;
  },

  async deleteSubscription(id: string): Promise<void> {
    await api.delete(`/app_subscriptions/${id}`);
  },

  async pauseSubscription(id: string, reason?: string): Promise<AppSubscription> {
    const response = await api.post(`/app_subscriptions/${id}/pause`, {
      reason
    });
    return response.data.data;
  },

  async resumeSubscription(id: string): Promise<AppSubscription> {
    const response = await api.post(`/app_subscriptions/${id}/resume`);
    return response.data.data;
  },

  async cancelSubscription(id: string, reason?: string): Promise<AppSubscription> {
    const response = await api.post(`/app_subscriptions/${id}/cancel`, {
      reason
    });
    return response.data.data;
  },

  async upgradePlan(id: string, newPlanId: string): Promise<AppSubscription> {
    const response = await api.post(`/app_subscriptions/${id}/upgrade_plan`, {
      app_plan_id: newPlanId
    });
    return response.data.data;
  },

  async downgradePlan(id: string, newPlanId: string): Promise<AppSubscription> {
    const response = await api.post(`/app_subscriptions/${id}/downgrade_plan`, {
      app_plan_id: newPlanId
    });
    return response.data.data;
  },

  async getUsage(id: string): Promise<SubscriptionUsage> {
    const response = await api.get(`/app_subscriptions/${id}/usage`);
    return response.data.data;
  },

  async getAnalytics(id: string): Promise<SubscriptionAnalytics> {
    const response = await api.get(`/app_subscriptions/${id}/analytics`);
    return response.data.data;
  }
};