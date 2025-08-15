import { api } from './api';

export interface Plan {
  id: string;
  name: string;
  price: {
    cents: number;
    currency_iso: string;
  } | number; // Support both new API format and legacy format
  interval?: string;
  billing_cycle?: string;
  billingCycle?: string; // Legacy camelCase support
  features: Record<string, any>;
  limits?: Record<string, any>;
  status: string;
  isPublic?: boolean;
  currency?: string;
  trialDays?: number;
}

export interface Subscription {
  id: string;
  status: string;
  currentPeriodStart: string;
  currentPeriodEnd: string;
  trialEndsAt?: string;
  canceledAt?: string;
  endsAt?: string;
  createdAt: string;
  updatedAt: string;
  plan: Plan;
}

export interface SubscriptionResponse {
  success: boolean;
  data?: Subscription | Subscription[];
  message?: string;
  error?: string;
  details?: string[];
}

export interface CreateSubscriptionRequest {
  planId: string;
  trialEndsAt?: string;
}

export interface UpdateSubscriptionRequest {
  planId: string;
}

class SubscriptionService {
  async getSubscriptions(): Promise<SubscriptionResponse> {
    try {
      const response = await api.get<SubscriptionResponse>('/subscriptions');
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to fetch subscriptions',
        details: error.response?.data?.details || []
      };
    }
  }

  async getSubscription(id: string): Promise<SubscriptionResponse> {
    try {
      const response = await api.get<SubscriptionResponse>(`/subscriptions/${id}`);
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to fetch subscription',
        details: error.response?.data?.details || []
      };
    }
  }

  async createSubscription(data: CreateSubscriptionRequest): Promise<SubscriptionResponse> {
    try {
      const response = await api.post<SubscriptionResponse>('/subscriptions', { subscription: data });
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to create subscription',
        details: error.response?.data?.details || []
      };
    }
  }

  async updateSubscription(id: string, data: UpdateSubscriptionRequest): Promise<SubscriptionResponse> {
    try {
      const response = await api.patch<SubscriptionResponse>(`/subscriptions/${id}`, { subscription: data });
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to update subscription',
        details: error.response?.data?.details || []
      };
    }
  }

  async cancelSubscription(id: string): Promise<SubscriptionResponse> {
    try {
      const response = await api.delete<SubscriptionResponse>(`/subscriptions/${id}`);
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to cancel subscription',
        details: error.response?.data?.details || []
      };
    }
  }
}

export const subscriptionService = new SubscriptionService();
export default subscriptionService;