import { api } from '@/shared/services/api';

// Types
export interface Worker {
  id: string;
  name: string;
  description?: string;
  roles: string[]; // Array of role names assigned to worker
  permissions: string[]; // Array of permission strings inherited from roles (read-only)
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
  system_workers: number;
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
  roles?: string[]; // Array of role names to assign
}

export interface UpdateWorkerData {
  name?: string;
  description?: string;
  roles?: string[]; // Array of role names to assign
}

export interface WorkerConfig {
  security: {
    token_rotation_enabled: boolean;
    token_expiry_days: number;
    require_ip_whitelist: boolean;
    allowed_ips: string[];
    max_concurrent_sessions: number;
    enforce_https: boolean;
  };
  rate_limiting: {
    enabled: boolean;
    requests_per_minute: number;
    burst_limit: number;
    throttle_delay_ms: number;
  };
  monitoring: {
    activity_logging: boolean;
    performance_tracking: boolean;
    error_reporting: boolean;
    metrics_retention_days: number;
  };
  notifications: {
    alert_on_failures: boolean;
    alert_threshold: number;
    notify_on_token_rotation: boolean;
    notify_on_suspension: boolean;
  };
  operational: {
    auto_cleanup_activities: boolean;
    cleanup_after_days: number;
    enable_health_checks: boolean;
    health_check_interval_minutes: number;
  };
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
    success_rate: number;
    avg_response_time: number;
    top_endpoints: { endpoint: string; count: number }[];
    actions: Record<string, number>;
    last_activity_at: string | null;
  };
  worker: {
    id: string;
    name: string;
    roles: string[];
    permissions: string[];
  };
}

class WorkerAPI {
  // Workers Management
  async getWorkers(): Promise<WorkerListResponse> {
    const response = await api.get('/workers');
    return response.data.data;
  }

  async getWorker(id: string): Promise<WorkerDetailsResponse> {
    const response = await api.get(`/workers/${id}`);
    return response.data.data;
  }

  async createWorker(data: CreateWorkerData): Promise<{ worker: Worker; message: string }> {
    const response = await api.post('/workers', { worker: data });
    return response.data.data;
  }

  async updateWorker(id: string, data: UpdateWorkerData): Promise<{ worker: Worker; message: string }> {
    const response = await api.patch(`/workers/${id}`, { worker: data });
    return response.data.data;
  }

  async deleteWorker(id: string): Promise<{ message: string }> {
    const response = await api.delete(`/workers/${id}`);
    return response.data.data;
  }

  async regenerateToken(id: string): Promise<{ worker: Worker; new_token: string; message: string }> {
    const response = await api.post(`/workers/${id}/regenerate_token`);
    return response.data.data;
  }

  async suspendWorker(id: string): Promise<{ worker: Worker; message: string }> {
    const response = await api.post(`/workers/${id}/suspend`);
    return response.data.data;
  }

  async activateWorker(id: string): Promise<{ worker: Worker; message: string }> {
    const response = await api.post(`/workers/${id}/activate`);
    return response.data.data;
  }

  async revokeWorker(id: string): Promise<{ worker: Worker; message: string }> {
    const response = await api.post(`/workers/${id}/revoke`);
    return response.data.data;
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
    const response = await api.get(`/workers/${workerId}/activities`, { params });
    return response.data;
  }

  async getWorkerActivity(workerId: string, activityId: string): Promise<{ activity: WorkerActivity; worker: { id: string; name: string } }> {
    const response = await api.get(`/workers/${workerId}/activities/${activityId}`);
    return response.data;
  }

  async getWorkerActivitySummary(
    workerId: string,
    hours = 24
  ): Promise<{
    worker: { id: string; name: string; roles: string[]; permissions: string[] };
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
    const response = await api.get(`/workers/${workerId}/activities/summary`, {
      params: { hours }
    });
    return response.data;
  }

  async cleanupWorkerActivities(
    workerId: string,
    days = 30
  ): Promise<{ message: string; deleted_count: number; cutoff_date: string }> {
    const response = await api.delete(`/workers/${workerId}/activities/cleanup`, {
      params: { days }
    });
    return response.data;
  }

  // Worker Configuration Management
  async getWorkerConfig(workerId: string): Promise<WorkerConfig> {
    const response = await api.get(`/workers/${workerId}/config`);
    return response.data.data;
  }

  async updateWorkerConfig(workerId: string, config: WorkerConfig): Promise<{ worker: Worker; config: WorkerConfig; message: string }> {
    const response = await api.put(`/workers/${workerId}/config`, { worker_config: config });
    return response.data.data;
  }

  async testWorker(workerId: string): Promise<{
    message: string;
    job_status: string;
    estimated_completion: string;
  }> {
    const response = await api.post(`/workers/${workerId}/test_worker`);
    return response.data.data;
  }

  async testWorkerHealth(workerId: string): Promise<{
    status: 'healthy' | 'warning' | 'error';
    checks: {
      connectivity: 'pass' | 'fail';
      authentication: 'pass' | 'fail';
      rate_limiting: 'pass' | 'fail';
      monitoring: 'pass' | 'fail';
    };
    response_time_ms: number;
    details: string[];
  }> {
    const response = await api.post(`/workers/${workerId}/health_check`);
    return response.data.data;
  }

  async resetWorkerConfig(workerId: string): Promise<{ worker: Worker; config: WorkerConfig; message: string }> {
    const response = await api.post(`/workers/${workerId}/config/reset`);
    return response.data.data;
  }
}

export const workerAPI = new WorkerAPI();
export default workerAPI;