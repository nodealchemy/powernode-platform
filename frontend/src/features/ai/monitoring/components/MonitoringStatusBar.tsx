import React from 'react';
import { Activity, Clock } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { VerdictBadge } from '@/shared/components/ui/VerdictBadge';
import { HealthStatus } from '@/shared/services/ai/MonitoringApiService';
import {
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
  return (
    <div className="flex items-center justify-between bg-theme-surface border border-theme rounded-lg p-4">
      <div className="flex items-center gap-4">
        <div className="flex items-center gap-2">
          <div className={`h-3 w-3 rounded-full ${getConnectionStatusColor(isConnected)}`} />
          <span className="text-sm font-medium text-theme-primary">
            {isConnected ? 'Connected' : 'Disconnected'}
          </span>
        </div>

        {systemHealth && (
          <div className="flex items-center gap-2">
            <Activity className="h-4 w-4 text-theme-tertiary" />
            <span className="text-sm text-theme-tertiary">System Health:</span>
            {systemHealth.rollup ? (
              <VerdictBadge verdict={systemHealth.rollup.verdict} size="sm" />
            ) : (
              <Badge variant="outline">Not measured</Badge>
            )}
          </div>
        )}

        {lastUpdate && (
          <div className="flex items-center gap-2">
            <Clock className="h-4 w-4 text-theme-tertiary" />
            <span className="text-sm text-theme-tertiary">
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
