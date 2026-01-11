import { api } from '@/shared/services/api';

// Types
export interface Service {
  id: string;
  name: string;
  description?: string;
  permissions: 'readonly' | 'standard' | 'admin' | 'super_admin';
  status: 'active' | 'suspended' | 'revoked';
  account_name: string;
  masked_token: string;
  token?: string; // Only available in details view
  request_count: number;
  last_seen_at: string | null;
  active_recently: boolean;
  created_at: string;
  updated_at: string;
  token_regenerated_at?: string;
}

export interface ServiceActivity {
  id: string;
  action: string;
  performed_at: string;
  ip_address?: string;
  user_agent?: string;
  successful: boolean;
  failed: boolean;
  duration?: number;
  response_status?: number;
  request_path?: string;
  error_message?: string;
  details?: Record<string, any>;
}

export interface ServiceListResponse {
  services: Service[];
  total: number;
  account_services: number;
}

export interface ServiceDetailsResponse {
  service: Service;
  activity_summary: {
    total_requests: number;
    successful_requests: number;
    failed_requests: number;
    unique_actions: string[];
    last_activity: string | null;
    requests_by_hour: Record<string, number>;
  };
  recent_activities: ServiceActivity[];
}

export interface CreateServiceData {
  name: string;
  description?: string;
  permissions?: 'readonly' | 'standard' | 'admin' | 'super_admin';
}

export interface UpdateServiceData {
  name?: string;
  description?: string;
  permissions?: 'readonly' | 'standard' | 'admin' | 'super_admin';
}

export interface ActivityListResponse {
  activities: ServiceActivity[];
  pagination: {
    page: number;
    per_page: number;
    total: number;
    total_pages: number;
  };
  summary: {
    total_recent: number;
    successful_recent: number;
    failed_recent: number;
    actions: Record<string, number>;
    last_activity_at: string | null;
  };
  service: {
    id: string;
    name: string;
    permissions: string;
  };
}

class ServiceAPI {
  // Services Management
  async getServices(): Promise<ServiceListResponse> {
    const response = await api.get('/admin/services');
    return response.data;
  }

  async getService(id: string): Promise<ServiceDetailsResponse> {
    const response = await api.get(`/admin/services/${id}`);
    return response.data;
  }

  async createService(data: CreateServiceData): Promise<{ service: Service; message: string }> {
    const response = await api.post('/admin/services', { service: data });
    return response.data;
  }

  async updateService(id: string, data: UpdateServiceData): Promise<{ service: Service; message: string }> {
    const response = await api.patch(`/admin/services/${id}`, { service: data });
    return response.data;
  }

  async deleteService(id: string): Promise<{ message: string }> {
    const response = await api.delete(`/admin/services/${id}`);
    return response.data;
  }

  async regenerateToken(id: string): Promise<{ service: Service; new_token: string; message: string }> {
    const response = await api.post(`/admin/services/${id}/regenerate_token`);
    return response.data;
  }

  async suspendService(id: string): Promise<{ service: Service; message: string }> {
    const response = await api.post(`/admin/services/${id}/suspend`);
    return response.data;
  }

  async activateService(id: string): Promise<{ service: Service; message: string }> {
    const response = await api.post(`/admin/services/${id}/activate`);
    return response.data;
  }

  async revokeService(id: string): Promise<{ service: Service; message: string }> {
    const response = await api.post(`/admin/services/${id}/revoke`);
    return response.data;
  }

  // Activities Management
  async getServiceActivities(
    serviceId: string,
    params?: {
      page?: number;
      per_page?: number;
      action?: string;
      status?: 'success' | 'failed';
      from?: string;
      to?: string;
    }
  ): Promise<ActivityListResponse> {
    const response = await api.get(`/admin/services/${serviceId}/activities`, { params });
    return response.data;
  }

  async getServiceActivity(serviceId: string, activityId: string): Promise<{ activity: ServiceActivity; service: { id: string; name: string } }> {
    const response = await api.get(`/admin/services/${serviceId}/activities/${activityId}`);
    return response.data;
  }

  async getServiceActivitySummary(
    serviceId: string,
    hours = 24
  ): Promise<{
    service: { id: string; name: string; permissions: string };
    time_range: { hours: number; from: string; to: string };
    summary: {
      total_requests: number;
      successful_requests: number;
      failed_requests: number;
      unique_actions: string[];
      last_activity: string | null;
      requests_by_hour: Record<string, number>;
      actions_breakdown: Record<string, number>;
      hourly_breakdown: Record<string, number>;
      success_rate: number;
      average_response_time?: number;
    };
  }> {
    const response = await api.get(`/admin/services/${serviceId}/activities/summary`, {
      params: { hours }
    });
    return response.data;
  }

  async cleanupServiceActivities(
    serviceId: string,
    days = 30
  ): Promise<{ message: string; deleted_count: number; cutoff_date: string }> {
    const response = await api.delete(`/admin/services/${serviceId}/activities/cleanup`, {
      params: { days }
    });
    return response.data;
  }
}

export const service_api = new ServiceAPI();
export default service_api;