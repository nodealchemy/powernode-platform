import { MonitoringDashboard, Alert as ApiAlert } from '@/shared/services/ai/MonitoringApiService';
import {
  MonitoringDashboardData,
  Alert
} from '@/shared/types/monitoring';

/**
 * Transform API dashboard response to internal MonitoringDashboardData type
 * Uses native backend overview data directly
 */
export const transformDashboardData = (dashboard: MonitoringDashboard): MonitoringDashboardData => {
  return {
    overview: {
      // Use native overview from backend
      total_providers: dashboard.providers?.length || 0,
      total_agents: dashboard.overview?.active_agents || dashboard.agents?.total || 0,
      total_workflows: dashboard.overview?.active_workflows || dashboard.workflows?.total || 0,
      active_conversations: dashboard.workflows?.running || 0,
      system_uptime: 0,
      last_updated: new Date().toISOString(),
      // Extended operational metrics
      total_executions_today: dashboard.overview?.total_executions_today || 0,
      total_cost_today: dashboard.overview?.total_cost_today || 0,
      avg_response_time: dashboard.overview?.avg_response_time || 0,
      success_rate: dashboard.overview?.success_rate || 0,
    },
    timestamp: new Date().toISOString(),
    health_score: dashboard.system_health?.uptime_percentage || 100,
    components: {}
  };
};

/**
 * Transform API alerts to internal Alert type
 */
export const transformAlerts = (apiAlerts: ApiAlert[]): Alert[] => {
  return apiAlerts.map(alert => ({
    id: alert.id,
    severity: alert.severity === 'critical' ? 'critical' : alert.severity === 'warning' ? 'high' : 'medium',
    component: alert.component,
    title: alert.message.split(':')[0] || 'Alert',
    message: alert.message,
    metadata: {},
    acknowledged: alert.acknowledged,
    acknowledged_at: null,
    acknowledged_by: null,
    resolved: alert.resolved,
    resolved_at: null,
    resolved_by: null,
    created_at: alert.timestamp
  }));
};
