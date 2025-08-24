import { api } from '@/shared/services/api';
import { 
  AppWebhook, 
  AppWebhookFormData, 
  AppWebhookFilters,
  AppWebhookDelivery 
} from '../types';

export const appWebhooksApi = {
  async getWebhooks(appId: string, filters: AppWebhookFilters = {}): Promise<{
    data: AppWebhook[];
    pagination: any;
  }> {
    const params = new URLSearchParams();
    if (filters.search) params.append('search', filters.search);
    if (filters.event_type) params.append('event_type', filters.event_type);
    if (filters.active !== undefined) params.append('active', filters.active.toString());
    if (filters.page) params.append('page', filters.page.toString());
    if (filters.per_page) params.append('per_page', filters.per_page.toString());

    const response = await api.get(`/apps/${appId}/webhooks?${params}`);
    return {
      data: response.data.data || response.data,
      pagination: response.data.pagination || { current_page: 1, total_pages: 1, total_count: 0, per_page: 20 }
    };
  },

  async getWebhook(appId: string, webhookId: string): Promise<AppWebhook> {
    const response = await api.get(`/apps/${appId}/webhooks/${webhookId}`);
    return response.data;
  },

  async createWebhook(appId: string, data: AppWebhookFormData): Promise<AppWebhook> {
    const response = await api.post(`/apps/${appId}/webhooks`, { app_webhook: data });
    return response.data;
  },

  async updateWebhook(appId: string, webhookId: string, data: Partial<AppWebhookFormData>): Promise<AppWebhook> {
    const response = await api.put(`/apps/${appId}/webhooks/${webhookId}`, { app_webhook: data });
    return response.data;
  },

  async deleteWebhook(appId: string, webhookId: string): Promise<void> {
    await api.delete(`/apps/${appId}/webhooks/${webhookId}`);
  },

  async activateWebhook(appId: string, webhookId: string): Promise<AppWebhook> {
    const response = await api.post(`/apps/${appId}/webhooks/${webhookId}/activate`);
    return response.data;
  },

  async deactivateWebhook(appId: string, webhookId: string): Promise<AppWebhook> {
    const response = await api.post(`/apps/${appId}/webhooks/${webhookId}/deactivate`);
    return response.data;
  },

  async testWebhook(appId: string, webhookId: string, testData?: any): Promise<{
    delivery_id: string;
    event_id: string;
    status: string;
    payload: any;
  }> {
    const response = await api.post(`/apps/${appId}/webhooks/${webhookId}/test`, {
      test_data: testData
    });
    return response.data;
  },

  async regenerateSecret(appId: string, webhookId: string): Promise<{
    secret_token: string;
    old_secret_preview: string;
    new_secret_preview: string;
  }> {
    const response = await api.post(`/apps/${appId}/webhooks/${webhookId}/regenerate_secret`);
    return response.data;
  },

  async getWebhookDeliveries(appId: string, webhookId: string, filters: {
    days?: number;
    status?: string;
    event_id?: string;
    page?: number;
    per_page?: number;
  } = {}): Promise<{
    data: AppWebhookDelivery[];
    pagination: any;
  }> {
    const params = new URLSearchParams();
    if (filters.days) params.append('days', filters.days.toString());
    if (filters.status) params.append('status', filters.status);
    if (filters.event_id) params.append('event_id', filters.event_id);
    if (filters.page) params.append('page', filters.page.toString());
    if (filters.per_page) params.append('per_page', filters.per_page.toString());

    const response = await api.get(`/apps/${appId}/webhooks/${webhookId}/deliveries?${params}`);
    return {
      data: response.data.data || response.data,
      pagination: response.data.pagination || { current_page: 1, total_pages: 1, total_count: 0, per_page: 20 }
    };
  },

  async getWebhookAnalytics(appId: string, webhookId: string, days: number = 30): Promise<{
    total_deliveries: number;
    deliveries_by_day: Record<string, number>;
    deliveries_by_status: Record<string, number>;
    success_rate: number;
    failure_rate: number;
    average_response_time: number;
    pending_deliveries: number;
    failed_deliveries: number;
    retry_stats: {
      total_retries: number;
      max_attempts: number;
      avg_attempts: number;
    };
  }> {
    const response = await api.get(`/apps/${appId}/webhooks/${webhookId}/analytics?days=${days}`);
    return response.data;
  }
};