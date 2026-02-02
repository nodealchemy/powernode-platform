import { api } from '@/shared/services/api';
import { getErrorMessage } from '@/shared/utils/errorHandling';
import type {
  UsageDashboardData,
  UsageMeter,
  UsageQuota,
  UsageEvent,
  UsageEventInput,
  BatchIngestionResult,
  BillingSummary,
  UsageSummary,
} from '../types';

interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
}

export const usageApi = {
  // Get usage dashboard data
  async getDashboard(): Promise<ApiResponse<UsageDashboardData>> {
    try {
      const response = await api.get('/api/v1/usage/dashboard');
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get all meters
  async getMeters(): Promise<ApiResponse<UsageMeter[]>> {
    try {
      const response = await api.get('/api/v1/usage/meters');
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get usage for a specific meter
  async getMeterUsage(
    slug: string,
    params?: {
      period_start?: string;
      period_end?: string;
    }
  ): Promise<ApiResponse<{
    meter: UsageMeter;
    period_start: string;
    period_end: string;
    total_quantity: number;
    event_count: number;
    calculated_cost: number;
    quota?: UsageQuota;
    events: UsageEvent[];
  }>> {
    try {
      const response = await api.get(`/api/v1/usage/meters/${slug}`, { params });
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get all quotas
  async getQuotas(): Promise<ApiResponse<UsageQuota[]>> {
    try {
      const response = await api.get('/api/v1/usage/quotas');
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Set a quota
  async setQuota(params: {
    meter_slug: string;
    soft_limit?: number;
    hard_limit?: number;
    allow_overage?: boolean;
    overage_rate?: number;
  }): Promise<ApiResponse<UsageQuota>> {
    try {
      const response = await api.post('/api/v1/usage/quotas', params);
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Reset quotas
  async resetQuotas(): Promise<ApiResponse<void>> {
    try {
      const response = await api.post('/api/v1/usage/quotas/reset');
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get usage history
  async getHistory(params?: {
    meter_slug?: string;
    days?: number;
  }): Promise<ApiResponse<{ history: UsageSummary[]; total_records: number }>> {
    try {
      const response = await api.get('/api/v1/usage/history', { params });
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get billing summary
  async getBillingSummary(params?: {
    period_start?: string;
    period_end?: string;
  }): Promise<ApiResponse<BillingSummary>> {
    try {
      const response = await api.get('/api/v1/usage/billing_summary', { params });
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Track a single event
  async trackEvent(event: UsageEventInput): Promise<ApiResponse<UsageEvent>> {
    try {
      const response = await api.post('/api/v1/usage_events', event);
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Track batch of events
  async trackEventsBatch(events: UsageEventInput[]): Promise<ApiResponse<BatchIngestionResult>> {
    try {
      const response = await api.post('/api/v1/usage_events/batch', { events });
      return response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Export usage data
  async exportUsage(params: {
    start_date: string;
    end_date: string;
    format?: 'json' | 'csv';
  }): Promise<ApiResponse<unknown> | Blob> {
    try {
      const response = await api.get('/api/v1/usage/export', {
        params,
        responseType: params.format === 'csv' ? 'blob' : 'json',
      });
      return params.format === 'csv' ? response.data : response.data;
    } catch {
      return { success: false, error: getErrorMessage(error) };
    }
  },
};
