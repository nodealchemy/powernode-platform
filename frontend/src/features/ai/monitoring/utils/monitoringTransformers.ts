import { Alert as ApiAlert } from '@/shared/services/ai/MonitoringApiService';
import { Alert } from '@/shared/types/monitoring';

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
    acknowledged_at: alert.acknowledged_at ?? null,
    acknowledged_by: alert.acknowledged_by ?? null,
    resolved: alert.resolved,
    resolved_at: alert.resolved_at ?? null,
    resolved_by: alert.resolved_by ?? null,
    created_at: alert.timestamp
  }));
};
