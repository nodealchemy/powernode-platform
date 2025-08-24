import { api } from '@/shared/services/api';

// Types
export interface Worker {
  id: string;
  name: string;
  description?: string;
  permissions: 'readonly' | 'standard' | 'admin' | 'super_admin';
  status: 'active' | 'suspended' | 'revoked';
  role: 'system' | 'account';
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

export interface WorkerActivity {
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

export interface WorkerListResponse {
  workers: Worker[];
  total: number;
  account_workers: number;
}

export interface WorkerDetailsResponse {
  worker: Worker;
  activity_summary: {
    total_requests: number;
    successful_requests: number;
    failed_requests: number;
    unique_actions: string[];
    last_activity: string | null;
    requests_by_hour: Record<string, number>;
  };
  recent_activities: WorkerActivity[];
}

export interface CreateWorkerData {
  name: string;
  description?: string;
  permissions?: 'readonly' | 'standard' | 'admin' | 'super_admin';
  role?: 'system' | 'account';
}

export interface UpdateWorkerData {
  name?: string;
  description?: string;
  permissions?: 'readonly' | 'standard' | 'admin' | 'super_admin';
}

export interface ActivityListResponse {
  activities: WorkerActivity[];
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
  worker: {
    id: string;
    name: string;
    permissions: string;
  };
}

class WorkerAPI {
  // Workers Management
  async getWorkers(): Promise<WorkerListResponse> {
    const response = await api.get('/admin/workers');
    return response.data;
  }

  async getWorker(id: string): Promise<WorkerDetailsResponse> {
    const response = await api.get(`/admin/workers/${id}`);
    return response.data;
  }

  async createWorker(data: CreateWorkerData): Promise<{ worker: Worker; message: string }> {
    const response = await api.post('/admin/workers', { worker: data });
    return response.data;
  }

  async updateWorker(id: string, data: UpdateWorkerData): Promise<{ worker: Worker; message: string }> {
    const response = await api.patch(`/admin/workers/${id}`, { worker: data });
    return response.data;
  }

  async deleteWorker(id: string): Promise<{ message: string }> {
    const response = await api.delete(`/admin/workers/${id}`);
    return response.data;
  }

  async regenerateToken(id: string): Promise<{ worker: Worker; new_token: string; message: string }> {
    const response = await api.post(`/admin/workers/${id}/regenerate_token`);
    return response.data;
  }

  async suspendWorker(id: string): Promise<{ worker: Worker; message: string }> {
    const response = await api.post(`/admin/workers/${id}/suspend`);
    return response.data;
  }

  async activateWorker(id: string): Promise<{ worker: Worker; message: string }> {
    const response = await api.post(`/admin/workers/${id}/activate`);
    return response.data;
  }

  async revokeWorker(id: string): Promise<{ worker: Worker; message: string }> {
    const response = await api.post(`/admin/workers/${id}/revoke`);
    return response.data;
  }


  // Activities Management
  async getWorkerActivities(
    workerId: string,
    params?: {
      page?: number;
      per_page?: number;
      action?: string;
      status?: 'success' | 'failed';
      from?: string;
      to?: string;
    }
  ): Promise<ActivityListResponse> {
    const response = await api.get(`/admin/workers/${workerId}/activities`, { params });
    return response.data;
  }

  async getWorkerActivity(workerId: string, activityId: string): Promise<{ activity: WorkerActivity; worker: { id: string; name: string } }> {
    const response = await api.get(`/admin/workers/${workerId}/activities/${activityId}`);
    return response.data;
  }

  async getWorkerActivitySummary(
    workerId: string,
    hours = 24
  ): Promise<{
    worker: { id: string; name: string; permissions: string };
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
    const response = await api.get(`/admin/workers/${workerId}/activities/summary`, {
      params: { hours }
    });
    return response.data;
  }

  async cleanupWorkerActivities(
    workerId: string,
    days = 30
  ): Promise<{ message: string; deleted_count: number; cutoff_date: string }> {
    const response = await api.delete(`/admin/workers/${workerId}/activities/cleanup`, {
      params: { days }
    });
    return response.data;
  }
}

export const workerAPI = new WorkerAPI();
export default workerAPI;