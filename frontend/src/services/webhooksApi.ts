import api from './api';

// Types
export interface WebhookEndpoint {
  id: string;
  url: string;
  description?: string;
  status: 'active' | 'inactive';
  event_types: string[];
  content_type: string;
  timeout_seconds: number;
  retry_limit: number;
  created_at: string;
  updated_at: string;
  last_delivery_at?: string;
  success_count: number;
  failure_count: number;
  created_by?: {
    id: string;
    email: string;
  };
}

export interface DetailedWebhookEndpoint extends WebhookEndpoint {
  secret_token: string;
  retry_backoff: 'linear' | 'exponential';
  recent_deliveries: WebhookDelivery[];
  delivery_stats: {
    total_deliveries: number;
    success_rate: number;
    average_response_time: number;
    last_success_at?: string;
    last_failure_at?: string;
  };
}

export interface WebhookDelivery {
  id: string;
  webhook_endpoint_id: string;
  event_type: string;
  status: 'pending' | 'successful' | 'failed' | 'max_retries_reached';
  http_status?: number;
  response_time_ms?: number;
  attempt_count: number;
  next_retry_at?: string;
  created_at: string;
  completed_at?: string;
  error_message?: string;
  webhook_endpoint?: {
    id: string;
    url: string;
  };
}

export interface WebhookStats {
  total_endpoints: number;
  active_endpoints: number;
  inactive_endpoints: number;
  total_deliveries_today: number;
  successful_deliveries_today: number;
  failed_deliveries_today: number;
}

export interface DetailedWebhookStats extends WebhookStats {
  most_active_endpoints: Record<string, number>;
  event_type_distribution: Record<string, number>;
  daily_delivery_trend: Record<string, number>;
  average_response_times: number;
  retry_statistics: {
    total_retries: number;
    pending_retries: number;
    max_retries_reached: number;
  };
}

export interface WebhookEventCategories {
  [category: string]: string[];
}

export interface WebhookFormData {
  url: string;
  description?: string;
  status?: 'active' | 'inactive';
  event_types: string[];
  content_type?: string;
  timeout_seconds?: number;
  retry_limit?: number;
  retry_backoff?: 'linear' | 'exponential';
}

export interface WebhookTestResponse {
  success: boolean;
  message?: string;
  data?: {
    webhook_id: string;
    test_payload: any;
    response: {
      status: number;
      response_time: number;
      success: boolean;
    };
  };
  error?: string;
}

export interface WebhooksResponse {
  success: boolean;
  data: {
    webhooks: WebhookEndpoint[];
    pagination: {
      current_page: number;
      per_page: number;
      total_pages: number;
      total_count: number;
    };
    stats: WebhookStats;
  };
  error?: string;
}

// API Service
export const webhooksApi = {
  // Get all webhook endpoints
  async getWebhooks(page = 1, perPage = 20): Promise<WebhooksResponse> {
    try {
      const response = await api.get(`/webhooks?page=${page}&per_page=${perPage}`);
      return response.data;
    } catch (error: any) {
      console.error('Failed to fetch webhooks:', error);
      return {
        success: false,
        data: {
          webhooks: [],
          pagination: {
            current_page: 1,
            per_page: perPage,
            total_pages: 0,
            total_count: 0
          },
          stats: {
            total_endpoints: 0,
            active_endpoints: 0,
            inactive_endpoints: 0,
            total_deliveries_today: 0,
            successful_deliveries_today: 0,
            failed_deliveries_today: 0
          }
        },
        error: error.response?.data?.error || 'Failed to fetch webhooks'
      };
    }
  },

  // Get single webhook endpoint
  async getWebhook(id: string): Promise<{ success: boolean; data?: DetailedWebhookEndpoint; error?: string }> {
    try {
      const response = await api.get(`/webhooks/${id}`);
      return response.data;
    } catch (error: any) {
      console.error('Failed to fetch webhook:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to fetch webhook'
      };
    }
  },

  // Create new webhook endpoint
  async createWebhook(webhookData: WebhookFormData): Promise<{ success: boolean; data?: DetailedWebhookEndpoint; message?: string; error?: string }> {
    try {
      const response = await api.post('/webhooks', { webhook: webhookData });
      return response.data;
    } catch (error: any) {
      console.error('Failed to create webhook:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to create webhook'
      };
    }
  },

  // Update webhook endpoint
  async updateWebhook(id: string, webhookData: Partial<WebhookFormData>): Promise<{ success: boolean; data?: DetailedWebhookEndpoint; message?: string; error?: string }> {
    try {
      const response = await api.put(`/webhooks/${id}`, { webhook: webhookData });
      return response.data;
    } catch (error: any) {
      console.error('Failed to update webhook:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to update webhook'
      };
    }
  },

  // Delete webhook endpoint
  async deleteWebhook(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.delete(`/webhooks/${id}`);
      return response.data;
    } catch (error: any) {
      console.error('Failed to delete webhook:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to delete webhook'
      };
    }
  },

  // Test webhook endpoint
  async testWebhook(id: string, eventType = 'test.webhook'): Promise<WebhookTestResponse> {
    try {
      const response = await api.post(`/webhooks/${id}/test`, { event_type: eventType });
      return response.data;
    } catch (error: any) {
      console.error('Failed to test webhook:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to test webhook'
      };
    }
  },

  // Toggle webhook status (active/inactive)
  async toggleWebhookStatus(id: string): Promise<{ success: boolean; data?: WebhookEndpoint; message?: string; error?: string }> {
    try {
      const response = await api.post(`/webhooks/${id}/toggle_status`);
      return response.data;
    } catch (error: any) {
      console.error('Failed to toggle webhook status:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to toggle webhook status'
      };
    }
  },

  // Get available event types
  async getAvailableEvents(): Promise<{ success: boolean; data?: { events: string[]; categories: WebhookEventCategories }; error?: string }> {
    try {
      const response = await api.get('/webhooks/available_events');
      return response.data;
    } catch (error: any) {
      console.error('Failed to fetch available events:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to fetch available events'
      };
    }
  },

  // Get delivery history
  async getDeliveryHistory(webhookId?: string, page = 1, perPage = 50): Promise<{
    success: boolean;
    data?: {
      deliveries: WebhookDelivery[];
      pagination: {
        current_page: number;
        per_page: number;
        total_pages: number;
        total_count: number;
      };
    };
    error?: string;
  }> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: perPage.toString()
      });
      
      if (webhookId) {
        params.append('webhook_id', webhookId);
      }

      const response = await api.get(`/webhooks/deliveries?${params}`);
      return response.data;
    } catch (error: any) {
      console.error('Failed to fetch delivery history:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to fetch delivery history'
      };
    }
  },

  // Get webhook statistics
  async getStats(): Promise<{ success: boolean; data?: DetailedWebhookStats; error?: string }> {
    try {
      const response = await api.get('/webhooks/stats');
      return response.data;
    } catch (error: any) {
      console.error('Failed to fetch webhook stats:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to fetch webhook stats'
      };
    }
  },

  // Retry failed deliveries
  async retryFailed(): Promise<{ success: boolean; data?: { retry_count: number; total_failed: number }; message?: string; error?: string }> {
    try {
      const response = await api.post('/webhooks/retry_failed');
      return response.data;
    } catch (error: any) {
      console.error('Failed to retry failed webhooks:', error);
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to retry failed webhooks'
      };
    }
  },

  // Helper methods
  getStatusColor(status: string): string {
    switch (status) {
      case 'active': return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'inactive': return 'bg-theme-surface text-theme-tertiary';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  },

  getDeliveryStatusColor(status: string): string {
    switch (status) {
      case 'successful': return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'pending': return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'failed': return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'max_retries_reached': return 'bg-theme-error bg-opacity-20 text-theme-error';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  },

  formatUrl(url: string, maxLength = 50): string {
    if (url.length <= maxLength) return url;
    return url.substring(0, maxLength - 3) + '...';
  },

  formatEventType(eventType: string): string {
    return eventType.split('.').map(part => 
      part.charAt(0).toUpperCase() + part.slice(1)
    ).join(' → ');
  },

  getSuccessRate(webhook: WebhookEndpoint): number {
    const total = webhook.success_count + webhook.failure_count;
    return total === 0 ? 0 : Math.round((webhook.success_count / total) * 100);
  },

  validateWebhookData(data: WebhookFormData): string[] {
    const errors: string[] = [];

    if (!data.url) {
      errors.push('URL is required');
    } else if (!this.isValidUrl(data.url)) {
      errors.push('Please enter a valid HTTP/HTTPS URL');
    }

    if (!data.event_types || data.event_types.length === 0) {
      errors.push('At least one event type must be selected');
    }

    if (data.timeout_seconds && (data.timeout_seconds < 1 || data.timeout_seconds > 300)) {
      errors.push('Timeout must be between 1 and 300 seconds');
    }

    if (data.retry_limit && (data.retry_limit < 0 || data.retry_limit > 10)) {
      errors.push('Retry limit must be between 0 and 10');
    }

    return errors;
  },

  isValidUrl(url: string): boolean {
    try {
      const urlObj = new URL(url);
      return urlObj.protocol === 'http:' || urlObj.protocol === 'https:';
    } catch {
      return false;
    }
  },

  getDefaultFormData(): WebhookFormData {
    return {
      url: '',
      description: '',
      status: 'active',
      event_types: [],
      content_type: 'application/json',
      timeout_seconds: 30,
      retry_limit: 3,
      retry_backoff: 'exponential'
    };
  }
};

export default webhooksApi;