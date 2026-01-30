import { apiClient } from '@/shared/services/apiClient';
import { PaginationInfo } from '../../types';

// Account Git Webhook Config types
export interface AccountGitWebhookConfig {
  id: string;
  name: string;
  url: string;
  description?: string;
  status: 'active' | 'inactive';
  is_active: boolean;
  event_types: string[];
  branch_filter?: string;
  branch_filter_type: 'none' | 'exact' | 'wildcard' | 'regex';
  branch_filter_enabled: boolean;
  content_type: 'application/json' | 'application/x-www-form-urlencoded';
  timeout_seconds: number;
  retry_limit: number;
  retry_backoff: 'linear' | 'exponential';
  custom_headers_count: number;
  success_count: number;
  failure_count: number;
  success_rate: number;
  health_status: 'unknown' | 'excellent' | 'good' | 'warning' | 'critical';
  last_delivery_at?: string;
  created_at: string;
  updated_at: string;
}

export interface AccountGitWebhookConfigDetail extends AccountGitWebhookConfig {
  masked_secret?: string;
  custom_headers: Record<string, string>;
  created_by?: {
    id: string;
    name: string;
    email: string;
  };
}

export interface AccountGitWebhookFormData {
  name: string;
  url: string;
  description?: string;
  status?: 'active' | 'inactive';
  is_active?: boolean;
  event_types?: string[];
  branch_filter?: string;
  branch_filter_type?: 'none' | 'exact' | 'wildcard' | 'regex';
  content_type?: 'application/json' | 'application/x-www-form-urlencoded';
  timeout_seconds?: number;
  retry_limit?: number;
  retry_backoff?: 'linear' | 'exponential';
  custom_headers?: Record<string, string>;
}

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Account Git Webhooks API
 * Manages account-level git webhook configurations
 */
export const accountWebhooksApi = {
  /**
   * Get all account webhooks
   */
  getAccountWebhooks: async (params?: {
    page?: number;
    per_page?: number;
    status?: 'active' | 'inactive';
    search?: string;
  }): Promise<{
    webhooks: AccountGitWebhookConfig[];
    pagination: PaginationInfo;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      webhooks: AccountGitWebhookConfig[];
      pagination: PaginationInfo;
    }>>('/git/account_webhooks', { params });
    return response.data.data;
  },

  /**
   * Get a specific account webhook
   */
  getAccountWebhook: async (id: string): Promise<AccountGitWebhookConfigDetail> => {
    const response = await apiClient.get<ApiResponse<{
      webhook: AccountGitWebhookConfigDetail;
    }>>(`/git/account_webhooks/${id}`);
    return response.data.data.webhook;
  },

  /**
   * Create a new account webhook
   */
  createAccountWebhook: async (
    data: AccountGitWebhookFormData
  ): Promise<AccountGitWebhookConfigDetail> => {
    const response = await apiClient.post<ApiResponse<{
      webhook: AccountGitWebhookConfigDetail;
    }>>('/git/account_webhooks', data);
    return response.data.data.webhook;
  },

  /**
   * Update an account webhook
   */
  updateAccountWebhook: async (
    id: string,
    data: Partial<AccountGitWebhookFormData>
  ): Promise<AccountGitWebhookConfigDetail> => {
    const response = await apiClient.patch<ApiResponse<{
      webhook: AccountGitWebhookConfigDetail;
    }>>(`/git/account_webhooks/${id}`, data);
    return response.data.data.webhook;
  },

  /**
   * Delete an account webhook
   */
  deleteAccountWebhook: async (id: string): Promise<{ message: string }> => {
    const response = await apiClient.delete<ApiResponse<{
      message: string;
    }>>(`/git/account_webhooks/${id}`);
    return response.data.data;
  },

  /**
   * Test an account webhook
   */
  testAccountWebhook: async (
    id: string
  ): Promise<{ message: string; test_payload: Record<string, unknown> }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      test_payload: Record<string, unknown>;
    }>>(`/git/account_webhooks/${id}/test`);
    return response.data.data;
  },

  /**
   * Toggle account webhook status
   */
  toggleAccountWebhookStatus: async (
    id: string
  ): Promise<{ webhook: AccountGitWebhookConfig; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      webhook: AccountGitWebhookConfig;
      message: string;
    }>>(`/git/account_webhooks/${id}/toggle_status`);
    return response.data.data;
  },

  /**
   * Regenerate account webhook secret
   */
  regenerateAccountWebhookSecret: async (
    id: string
  ): Promise<{ webhook: AccountGitWebhookConfigDetail; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      webhook: AccountGitWebhookConfigDetail;
      message: string;
    }>>(`/git/account_webhooks/${id}/regenerate_secret`);
    return response.data.data;
  },

  /**
   * Get available event types for account webhooks
   */
  getAvailableEventTypes: async (): Promise<{
    event_types: string[];
    event_categories: Record<string, string[]>;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      event_types: string[];
      event_categories: Record<string, string[]>;
    }>>('/git/account_webhooks/available_events');
    return response.data.data;
  },
};
