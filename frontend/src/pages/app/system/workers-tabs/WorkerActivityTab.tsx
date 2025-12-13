import React, { useState } from 'react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { RefreshCw } from 'lucide-react';
import type { WorkerActivityTabProps } from './types';

export const WorkerActivityTab: React.FC<WorkerActivityTabProps> = ({
  workers,
  onRefresh
}) => {
  const [timeRange, setTimeRange] = useState<'1h' | '24h' | '7d' | '30d'>('24h');

  const getActivityData = () => {
    return workers
      .filter(w => w.active_recently)
      .map(w => ({
        name: w.name,
        requests: w.request_count,
        lastSeen: w.last_seen_at,
        status: w.status,
        account: w.account_name,
        isSystem: w.account_name === 'System'
      }))
      .sort((a, b) => {
        // System workers first, then by request count
        if (a.isSystem && !b.isSystem) return -1;
        if (!a.isSystem && b.isSystem) return 1;

        return b.requests - a.requests;
      });
  };

  const activityData = getActivityData();

  return (
    <div className="space-y-6">
      {/* Activity Controls */}
      <Card className="p-6">
        <FlexBetween className="mb-4">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Activity Monitoring</h3>
            <p className="text-sm text-theme-secondary">
              Monitor worker activity and performance metrics
            </p>
          </div>
          <FlexItemsCenter gap="sm">
            <select
              value={timeRange}
              onChange={(e) => setTimeRange(e.target.value as '1h' | '24h' | '7d' | '30d')}
              className="px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
            >
              <option value="1h">Last Hour</option>
              <option value="24h">Last 24 Hours</option>
              <option value="7d">Last 7 Days</option>
              <option value="30d">Last 30 Days</option>
            </select>
            <Button onClick={onRefresh} variant="secondary" size="sm">
              <RefreshCw className="w-4 h-4 mr-2" />
              Refresh
            </Button>
          </FlexItemsCenter>
        </FlexBetween>

        {/* Activity Summary */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="text-sm text-theme-secondary mb-1">Active Workers</div>
            <div className="text-2xl font-bold text-theme-success">
              {workers.filter(w => w.active_recently).length}
            </div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="text-sm text-theme-secondary mb-1">Total Requests</div>
            <div className="text-2xl font-bold text-theme-primary">
              {workers.reduce((sum, w) => sum + w.request_count, 0).toLocaleString()}
            </div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="text-sm text-theme-secondary mb-1">Avg Requests/Worker</div>
            <div className="text-2xl font-bold text-theme-info">
              {Math.round(workers.reduce((sum, w) => sum + w.request_count, 0) / workers.length) || 0}
            </div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="text-sm text-theme-secondary mb-1">Health Score</div>
            <div className="text-2xl font-bold text-theme-success">98%</div>
          </div>
        </div>
      </Card>

      {/* Activity List */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Worker Activity</h3>
        <div className="space-y-3">
          {activityData.length === 0 ? (
            <p className="text-center text-theme-secondary py-8">No activity data available</p>
          ) : (
            activityData.map((worker, index) => (
              <div
                key={worker.name}
                className={`p-4 border border-theme rounded-lg ${
                  worker.isSystem ? 'bg-gradient-to-r from-theme-info/5 to-transparent border-theme-info/30' : ''
                }`}
              >
                <FlexBetween>
                  <div className="flex items-center space-x-3">
                    <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
                      worker.isSystem ? 'bg-theme-info/20 text-theme-info' : 'bg-theme-primary/10 text-theme-primary'
                    }`}>
                      {worker.isSystem ? '⚙️' : index + 1}
                    </div>
                    <div>
                      <div className="font-medium text-theme-primary">
                        {worker.name}
                        {worker.isSystem && (
                          <span className="ml-2 px-2 py-0.5 text-xs bg-theme-info/10 text-theme-info rounded-full">
                            SYSTEM
                          </span>
                        )}
                      </div>
                      <div className="text-sm text-theme-secondary">{worker.account}</div>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="font-medium text-theme-primary">
                      {worker.requests.toLocaleString()} requests
                    </div>
                    <div className="text-sm text-theme-secondary">
                      {worker.lastSeen ?
                        `Last seen ${new Date(worker.lastSeen).toLocaleDateString()}` :
                        'Never seen'
                      }
                    </div>
                  </div>
                </FlexBetween>
              </div>
            ))
          )}
        </div>
      </Card>
    </div>
  );
};
