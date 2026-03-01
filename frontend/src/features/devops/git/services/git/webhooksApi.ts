import { apiClient } from '@/shared/services/apiClient';
import {
  GitWebhookEvent,
  GitWebhookEventDetail,
  PaginationInfo,
  WebhookEventStats,
} from '../../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Git Webhooks API
 * Manages webhook events and processing
 */
export const webhooksApi = {
  /**
   * Get webhook events
   */
  getWebhookEvents: async (params?: {
    page?: number;
    per_page?: number;
    event_type?: string;
    status?: string;
    repository_id?: string;
    provider_id?: string;
    since?: string;
    until?: string;
  }): Promise<{
    events: GitWebhookEvent[];
    pagination: PaginationInfo;
    stats: WebhookEventStats;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      events: GitWebhookEvent[];
      pagination: PaginationInfo;
      stats: WebhookEventStats;
    }>>('/git/webhook_events', { params });
    return response.data.data;
  },

  /**
   * Get a specific webhook event
   */
  getWebhookEvent: async (id: string): Promise<GitWebhookEventDetail> => {
    const response = await apiClient.get<ApiResponse<{
      event: GitWebhookEventDetail;
    }>>(`/git/webhook_events/${id}`);
    return response.data.data.event;
  },

  /**
   * Retry a webhook event
   */
  retryWebhookEvent: async (
    id: string
  ): Promise<{ message: string; event: GitWebhookEvent }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      event: GitWebhookEvent;
    }>>(`/git/webhook_events/${id}/retry`);
    return response.data.data;
  },

  /**
   * Redeliver a webhook event (creates a new event with the same payload)
   */
  redeliverWebhookEvent: async (
    id: string
  ): Promise<{
    message: string;
    original_event: GitWebhookEvent;
    new_event: GitWebhookEvent;
  }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      original_event: GitWebhookEvent;
      new_event: GitWebhookEvent;
    }>>(`/git/webhook_events/${id}/redeliver`);
    return response.data.data;
  },

  /**
   * Get webhook event statistics
   */
  getWebhookStats: async (params?: {
    provider_id?: string;
    days?: number;
  }): Promise<WebhookEventStats> => {
    const response = await apiClient.get<ApiResponse<{
      stats: WebhookEventStats;
    }>>('/git/webhook_events/stats', { params });
    return response.data.data.stats;
  },
};
