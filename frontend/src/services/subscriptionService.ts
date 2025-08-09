import apiClient from './api';

export interface Plan {
  id: string;
  name: string;
  price: number;
  interval: string;
  features: Record<string, any>;
  limits?: Record<string, any>;
  status: string;
  isPublic?: boolean;
  billingCycle: string;
  currency: string;
  trialDays: number;
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
      const response = await apiClient.get<SubscriptionResponse>('/subscriptions');
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
      const response = await apiClient.get<SubscriptionResponse>(`/subscriptions/${id}`);
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
      const response = await apiClient.post<SubscriptionResponse>('/subscriptions', { subscription: data });
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
      const response = await apiClient.patch<SubscriptionResponse>(`/subscriptions/${id}`, { subscription: data });
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
      const response = await apiClient.delete<SubscriptionResponse>(`/subscriptions/${id}`);
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