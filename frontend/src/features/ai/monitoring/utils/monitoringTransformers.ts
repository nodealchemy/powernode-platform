import { MonitoringDashboard, HealthStatus, Alert as ApiAlert } from '@/shared/services/ai/MonitoringApiService';
import {
  MonitoringDashboardData,
  SystemHealthData,
  Alert
} from '@/shared/types/monitoring';

/**
 * Transform API dashboard response to internal MonitoringDashboardData type
 */
export const transformDashboardData = (dashboard: MonitoringDashboard): MonitoringDashboardData => {
  return {
    overview: {
      total_providers: dashboard.providers?.length || 0,
      total_agents: dashboard.agents?.total || 0,
      total_workflows: dashboard.workflows?.total || 0,
      active_conversations: dashboard.workflows?.running || 0,
      system_uptime: 0,
      last_updated: new Date().toISOString()
    },
    timestamp: new Date().toISOString(),
    health_score: dashboard.system_health?.uptime_percentage || 100,
    components: {}
  };
};

/**
 * Transform API health status to internal SystemHealthData type
 */
export const transformHealthData = (health: HealthStatus): SystemHealthData => {
  const statusScore = health.status === 'healthy' ? 95 : health.status === 'degraded' ? 70 : 40;
  const defaultComponentHealth = {
    health_score: statusScore,
    status: health.status === 'healthy' ? 'healthy' as const : 'degraded' as const,
    active_count: 0,
    issues: []
  };

  return {
    overall_health: statusScore,
    status: health.status === 'healthy' ? 'excellent' : health.status === 'degraded' ? 'fair' : 'critical',
    components: {
      providers: defaultComponentHealth,
      agents: defaultComponentHealth,
      workflows: defaultComponentHealth,
      conversations: defaultComponentHealth,
      infrastructure: defaultComponentHealth
    },
    alerts: {
      active: 0,
      high_priority: 0,
      medium_priority: 0,
      low_priority: 0,
      by_component: {},
      recent_count: 0
    },
    recommendations: [],
    last_updated: health.timestamp
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
