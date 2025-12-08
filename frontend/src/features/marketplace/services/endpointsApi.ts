import { api } from '@/shared/services/api';
import { 
  AppEndpoint, 
  AppEndpointFormData, 
  AppEndpointFilters
} from '../types';

export interface PaginationInfo {
  current_page: number;
  total_pages: number;
  total_count: number;
  per_page: number;
}

export const appEndpointsApi = {
  async getEndpoints(appId: string, filters: AppEndpointFilters = {}): Promise<{
    data: AppEndpoint[];
    pagination: PaginationInfo;
  }> {
    const params = new URLSearchParams();
    if (filters.search) params.append('search', filters.search);
    if (filters.method) params.append('method', filters.method);
    if (filters.active !== undefined) params.append('active', filters.active.toString());
    if (filters.version) params.append('version', filters.version);
    if (filters.page) params.append('page', filters.page.toString());
    if (filters.per_page) params.append('per_page', filters.per_page.toString());

    const response = await api.get(`/apps/${appId}/endpoints?${params}`);
    return {
      data: response.data.data || response.data,
      pagination: response.data.pagination || { current_page: 1, total_pages: 1, total_count: 0, per_page: 20 }
    };
  },

  async getEndpoint(appId: string, endpointId: string): Promise<AppEndpoint> {
    const response = await api.get(`/apps/${appId}/endpoints/${endpointId}`);
    return response.data;
  },

  async createEndpoint(appId: string, data: AppEndpointFormData): Promise<AppEndpoint> {
    const response = await api.post(`/apps/${appId}/endpoints`, { app_endpoint: data });
    return response.data;
  },

  async updateEndpoint(appId: string, endpointId: string, data: Partial<AppEndpointFormData>): Promise<AppEndpoint> {
    const response = await api.put(`/apps/${appId}/endpoints/${endpointId}`, { app_endpoint: data });
    return response.data;
  },

  async deleteEndpoint(appId: string, endpointId: string): Promise<void> {
    await api.delete(`/apps/${appId}/endpoints/${endpointId}`);
  },

  async activateEndpoint(appId: string, endpointId: string): Promise<AppEndpoint> {
    const response = await api.post(`/apps/${appId}/endpoints/${endpointId}/activate`);
    return response.data;
  },

  async deactivateEndpoint(appId: string, endpointId: string): Promise<AppEndpoint> {
    const response = await api.post(`/apps/${appId}/endpoints/${endpointId}/deactivate`);
    return response.data;
  },

  async testEndpoint(appId: string, endpointId: string, testData?: Record<string, unknown>, testHeaders?: Record<string, string>): Promise<{
    call_id: string;
    status_code: number;
    response_time_ms: number;
    test_result: string;
  }> {
    const response = await api.post(`/apps/${appId}/endpoints/${endpointId}/test`, {
      test_data: testData,
      test_headers: testHeaders
    });
    return response.data;
  },

  async getEndpointAnalytics(appId: string, endpointId: string, days: number = 30): Promise<{
    total_calls: number;
    calls_by_day: Record<string, number>;
    calls_by_status: Record<string, number>;
    average_response_time: number;
    success_rate: number;
    error_rate: number;
    top_errors: Record<string, number>;
  }> {
    const response = await api.get(`/apps/${appId}/endpoints/${endpointId}/analytics?days=${days}`);
    return response.data;
  }
};