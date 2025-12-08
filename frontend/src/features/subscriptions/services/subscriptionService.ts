import { api } from '@/shared/services/api';

/**
 * HTTP Error Response Structure
 */
interface HttpErrorResponse {
  response?: {
    data?: {
      error?: string;
      details?: string[];
    };
  };
}

/**
 * @deprecated Use Plan from '@/features/plans/services/plansApi' instead
 * Kept for backward compatibility with subscription service responses
 */
export interface Plan {
  id: string;
  name: string;
  price: {
    cents: number;
    currency_iso: string;
  } | number;
  interval?: string;
  billing_cycle?: string;
  billingCycle?: string;
  features: Record<string, boolean | string | number>;
  limits?: Record<string, number>;
  status: string;
  isPublic?: boolean;
  currency?: string;
  trialDays?: number;
}

/**
 * @deprecated Use Subscription from '@/shared/types' instead
 * This interface uses camelCase - modern code should use snake_case version from shared/types
 */
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
  plan_id: string;
  trial_ends_at?: string;
}

export interface UpdateSubscriptionRequest {
  plan_id: string;
}

/**
 * @module SubscriptionService
 * @description Subscription lifecycle management service.
 *
 * RESPONSIBILITY: All subscription CRUD operations via /subscriptions/* endpoints
 * NOT RESPONSIBLE FOR: Billing, invoices, payment methods
 *
 * Integrates with Redux subscriptionSlice for state management.
 * @see Use billingApi for billing operations and payment processing
 */
class SubscriptionService {
  async getSubscriptions(): Promise<SubscriptionResponse> {
    try {
      const response = await api.get<SubscriptionResponse>('/subscriptions');
      return response.data;
    } catch (error: unknown) {
      const httpError = error as HttpErrorResponse;
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to fetch subscriptions',
        details: httpError.response?.data?.details || []
      };
    }
  }

  async getSubscription(id: string): Promise<SubscriptionResponse> {
    try {
      const response = await api.get<SubscriptionResponse>(`/subscriptions/${id}`);
      return response.data;
    } catch (error: unknown) {
      const httpError = error as HttpErrorResponse;
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to fetch subscription',
        details: httpError.response?.data?.details || []
      };
    }
  }

  async createSubscription(data: CreateSubscriptionRequest): Promise<SubscriptionResponse> {
    try {
      const response = await api.post<SubscriptionResponse>('/subscriptions', { subscription: data });
      return response.data;
    } catch (error: unknown) {
      const httpError = error as HttpErrorResponse;
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to create subscription',
        details: httpError.response?.data?.details || []
      };
    }
  }

  async updateSubscription(id: string, data: UpdateSubscriptionRequest): Promise<SubscriptionResponse> {
    try {
      const response = await api.patch<SubscriptionResponse>(`/subscriptions/${id}`, { subscription: data });
      return response.data;
    } catch (error: unknown) {
      const httpError = error as HttpErrorResponse;
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to update subscription',
        details: httpError.response?.data?.details || []
      };
    }
  }

  async cancelSubscription(id: string): Promise<SubscriptionResponse> {
    try {
      const response = await api.delete<SubscriptionResponse>(`/subscriptions/${id}`);
      return response.data;
    } catch (error: unknown) {
      const httpError = error as HttpErrorResponse;
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to cancel subscription',
        details: httpError.response?.data?.details || []
      };
    }
  }
}

export const subscriptionService = new SubscriptionService();