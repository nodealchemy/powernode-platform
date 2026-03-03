import { apiClient } from '@/shared/services/apiClient';

export interface DevopsOverviewResponse {
  source_control: {
    providers: { total: number; active: number; by_type: Record<string, number> };
    repositories: { total: number; active: number; with_webhook: number };
    credentials: { total: number; healthy: number; unhealthy: number; expires_soon: number };
  };
  ci_cd: {
    pipelines: { total: number; active: number };
    pipeline_runs: {
      total: number;
      successful: number;
      failed: number;
      running: number;
      today: number;
      success_rate: number;
    };
    runners: { total: number; online: number; offline: number; busy: number };
    schedules: { total: number; active: number };
  };
  infrastructure: {
    containers: {
      total: number;
      active: number;
      completed: number;
      failed: number;
      finished: number;
      success_rate: number;
    };
    swarm: { clusters: number; connected: number };
    docker: { hosts: number; connected: number };
  };
  connections: {
    integrations: { total: number; active: number; healthy: number; errored: number };
    webhooks: { total: number; processed_today: number; failed_today: number };
    api_keys: { total: number };
  };
  alerts: Array<{ level: 'warning' | 'error'; message: string; section: string }>;
}

export const devopsOverviewApi = {
  getOverview: async (refresh = false): Promise<DevopsOverviewResponse> => {
    const params = refresh ? '?refresh=true' : '';
    const response = await apiClient.get(`/devops/overview${params}`);
    return response.data.data;
  },
};
