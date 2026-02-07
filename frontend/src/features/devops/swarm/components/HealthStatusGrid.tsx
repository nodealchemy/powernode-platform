import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import { swarmApi } from '../services/swarmApi';
import type { ClusterHealthSummary, SwarmClusterSummary } from '../types';

interface HealthStatusGridProps {
  healthData: ClusterHealthSummary[];
  clusterNames?: SwarmClusterSummary[];
  isLoading?: boolean;
}

export const HealthStatusGrid: React.FC<HealthStatusGridProps> = ({ healthData, clusterNames, isLoading }) => {
  if (isLoading && healthData.length === 0) {
    return <p className="text-center py-8 text-theme-tertiary">Loading health data...</p>;
  }

  if (healthData.length === 0) {
    return <p className="text-center py-8 text-theme-tertiary">No health data available.</p>;
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      {healthData.map((health) => {
        const clusterName = clusterNames?.find((c) => c.id === health.cluster_id)?.name || health.cluster_id;
        const statusColor = swarmApi.getClusterStatusColor(health.status);
        const hasAlerts = health.alerts.length > 0;

        return (
          <Card key={health.cluster_id} variant="default" padding="lg">
            <div className="flex items-start justify-between mb-4">
              <h3 className="text-base font-semibold text-theme-primary">{clusterName}</h3>
              <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusColor}`}>
                {health.status}
              </span>
            </div>

            <div className="grid grid-cols-3 gap-3 mb-4">
              <div className="text-center p-2 rounded bg-theme-surface">
                <p className="text-lg font-bold text-theme-primary">{health.node_health.ready}/{health.node_health.total}</p>
                <p className="text-xs text-theme-tertiary">Nodes Ready</p>
              </div>
              <div className="text-center p-2 rounded bg-theme-surface">
                <p className="text-lg font-bold text-theme-primary">{health.service_health.healthy}/{health.service_health.total}</p>
                <p className="text-xs text-theme-tertiary">Services Healthy</p>
              </div>
              <div className="text-center p-2 rounded bg-theme-surface">
                <p className={`text-lg font-bold ${swarmApi.getHealthPercentageColor(health.service_health.avg_health_percentage)}`}>
                  {Math.round(health.service_health.avg_health_percentage)}%
                </p>
                <p className="text-xs text-theme-tertiary">Avg Health</p>
              </div>
            </div>

            <div className="flex items-center gap-4 mb-3 text-xs">
              <span className="text-theme-secondary">
                Managers: <span className="font-semibold text-theme-primary">{health.node_health.managers}</span>
              </span>
              <span className="text-theme-secondary">
                Workers: <span className="font-semibold text-theme-primary">{health.node_health.workers}</span>
              </span>
              {health.node_health.down > 0 && (
                <span className="text-theme-error font-semibold">
                  {health.node_health.down} down
                </span>
              )}
            </div>

            {(health.recent_events.critical > 0 || health.recent_events.warning > 0) && (
              <div className="flex items-center gap-3 mb-3 text-xs">
                {health.recent_events.critical > 0 && (
                  <span className="px-2 py-0.5 rounded bg-theme-error bg-opacity-10 text-theme-error font-medium">
                    {health.recent_events.critical} critical
                  </span>
                )}
                {health.recent_events.warning > 0 && (
                  <span className="px-2 py-0.5 rounded bg-theme-warning bg-opacity-10 text-theme-warning font-medium">
                    {health.recent_events.warning} warnings
                  </span>
                )}
                {health.recent_events.unacknowledged > 0 && (
                  <span className="text-theme-tertiary">
                    {health.recent_events.unacknowledged} unacknowledged
                  </span>
                )}
              </div>
            )}

            {hasAlerts && (
              <div className="border-t border-theme pt-3 space-y-1">
                {health.alerts.slice(0, 3).map((alert, i) => (
                  <div key={i} className={`text-xs px-2 py-1 rounded ${swarmApi.getEventSeverityColor(alert.severity)}`}>
                    {alert.message}
                  </div>
                ))}
                {health.alerts.length > 3 && (
                  <p className="text-xs text-theme-tertiary">+{health.alerts.length - 3} more alerts</p>
                )}
              </div>
            )}
          </Card>
        );
      })}
    </div>
  );
};
