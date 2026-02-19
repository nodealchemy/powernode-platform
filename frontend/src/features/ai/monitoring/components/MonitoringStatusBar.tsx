import React from 'react';
import { Activity, Clock } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { HealthStatus } from '@/shared/services/ai/MonitoringApiService';
import {
  getHealthScoreColor,
  getConnectionStatusColor,
  formatLastUpdate
} from '../utils';

interface MonitoringStatusBarProps {
  isConnected: boolean;
  systemHealth: HealthStatus | null;
  lastUpdate: Date | null;
  timeRange: string;
  onTimeRangeChange: (value: string) => void;
}

export const MonitoringStatusBar: React.FC<MonitoringStatusBarProps> = ({
  isConnected,
  systemHealth,
  lastUpdate,
  timeRange,
  onTimeRangeChange
}) => {
  // Derive display status label from health score
  const getStatusLabel = (score: number): string => {
    if (score >= 90) return 'excellent';
    if (score >= 70) return 'good';
    if (score >= 50) return 'fair';
    return 'critical';
  };

  return (
    <div className="flex items-center justify-between bg-theme-surface border border-theme-border rounded-lg p-4">
      <div className="flex items-center gap-4">
        <div className="flex items-center gap-2">
          <div className={`h-3 w-3 rounded-full ${getConnectionStatusColor(isConnected)}`} />
          <span className="text-sm font-medium text-theme-primary">
            {isConnected ? 'Connected' : 'Disconnected'}
          </span>
        </div>

        {systemHealth && (
          <div className="flex items-center gap-2">
            <Activity className="h-4 w-4 text-theme-muted" />
            <span className="text-sm text-theme-muted">System Health:</span>
            <span className={`text-sm font-medium ${getHealthScoreColor(systemHealth.health_score)}`}>
              {systemHealth.health_score.toFixed(1)}%
            </span>
            <Badge variant={
              systemHealth.health_score >= 90 ? 'success' :
              systemHealth.health_score >= 70 ? 'info' :
              systemHealth.health_score >= 50 ? 'warning' : 'danger'
            }>
              {getStatusLabel(systemHealth.health_score)}
            </Badge>
          </div>
        )}

        {lastUpdate && (
          <div className="flex items-center gap-2">
            <Clock className="h-4 w-4 text-theme-muted" />
            <span className="text-sm text-theme-muted">
              Updated {formatLastUpdate(lastUpdate)}
            </span>
          </div>
        )}
      </div>

      <div className="flex items-center gap-2">
        <Select
          value={timeRange}
          onValueChange={onTimeRangeChange}
          disabled={!isConnected}
        >
          <option value="5m">Last 5 minutes</option>
          <option value="15m">Last 15 minutes</option>
          <option value="1h">Last hour</option>
          <option value="6h">Last 6 hours</option>
          <option value="24h">Last 24 hours</option>
          <option value="7d">Last 7 days</option>
        </Select>

      </div>
    </div>
  );
};
