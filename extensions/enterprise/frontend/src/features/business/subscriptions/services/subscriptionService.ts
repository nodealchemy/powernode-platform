import { api } from '@/shared/services/api';
import type { Subscription } from '@/shared/types';

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

export interface PauseSubscriptionRequest {
  reason?: string;
}

export interface ProrationPreview {
  proration_amount_cents: number;
  days_remaining: number;
  days_in_period: number;
  proration_factor: number;
  new_plan_prorated_cents: number;
  old_plan_credit_cents: number;
  is_upgrade: boolean;
}

export interface ProrationPreviewResponse {
  success: boolean;
  data?: {
    current_plan: {
      id: string;
      name: string;
      price_cents: number;
      billing_cycle: string;
    };
    new_plan: {
      id: string;
      name: string;
      price_cents: number;
      billing_cycle: string;
    };
    proration: ProrationPreview;
    effective_date: string;
    billing_cycle_end: string;
  };
  message?: string;
  error?: string;
  details?: string[];
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
    } catch (error) {
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
    } catch (error) {
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
    } catch (error) {
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
    } catch (error) {
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
    } catch (error) {
      const httpError = error as HttpErrorResponse;
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to cancel subscription',
        details: httpError.response?.data?.details || []
      };
    }
  }

  /**
   * Pause a subscription.
   * Subscription must be in 'active' or 'trialing' status to be paused.
   */
  async pauseSubscription(id: string, reason?: string): Promise<SubscriptionResponse> {
    try {
      const response = await api.post<SubscriptionResponse>(`/subscriptions/${id}/pause`, { reason });
      return response.data;
    } catch (error) {
      const httpError = error as HttpErrorResponse;
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to pause subscription',
        details: httpError.response?.data?.details || []
      };
    }
  }

  /**
   * Resume a paused subscription.
   * Subscription must be in 'paused' status to be resumed.
   */
  async resumeSubscription(id: string): Promise<SubscriptionResponse> {
    try {
      const response = await api.post<SubscriptionResponse>(`/subscriptions/${id}/resume`);
      return response.data;
    } catch (error) {
      const httpError = error as HttpErrorResponse;
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to resume subscription',
        details: httpError.response?.data?.details || []
      };
    }
  }

  /**
   * Preview proration for a plan change.
   * Returns the calculated proration amount and details for upgrading or downgrading.
   */
  async previewPlanChange(subscriptionId: string, newPlanId: string): Promise<ProrationPreviewResponse> {
    try {
      const response = await api.get<ProrationPreviewResponse>(
        `/subscriptions/${subscriptionId}/preview_proration?new_plan_id=${newPlanId}`
      );
      return response.data;
    } catch (error) {
      const httpError = error as HttpErrorResponse;
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to preview plan change',
        details: httpError.response?.data?.details || []
      };
    }
  }
}

export const subscriptionService = new SubscriptionService();