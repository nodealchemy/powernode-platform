import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { RefreshCw } from 'lucide-react';
import type { WorkerOverviewTabProps } from './types';

export const WorkerOverviewTab: React.FC<WorkerOverviewTabProps> = ({
  workers,
  stats,
  onRefresh
}) => {
  const recentWorkers = workers
    .sort((a, b) => {
      // System workers first, then by creation date
      const aIsSystem = a.account_name === 'System';
      const bIsSystem = b.account_name === 'System';

      if (aIsSystem && !bIsSystem) return -1;
      if (!aIsSystem && bIsSystem) return 1;

      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
    })
    .slice(0, 5);

  const activeWorkers = workers
    .filter(w => w.active_recently)
    .sort((a, b) => {
      // System workers first, then by request count
      const aIsSystem = a.account_name === 'System';
      const bIsSystem = b.account_name === 'System';

      if (aIsSystem && !bIsSystem) return -1;
      if (!aIsSystem && bIsSystem) return 1;

      return b.request_count - a.request_count;
    })
    .slice(0, 5);

  return (
    <div className="space-y-6">
      {/* Quick Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <Card className="p-6">
          <FlexBetween className="mb-4">
            <h3 className="text-lg font-medium text-theme-primary">Status Distribution</h3>
            <Button onClick={onRefresh} variant="secondary" size="sm">
              <RefreshCw className="w-4 h-4" />
            </Button>
          </FlexBetween>
          <div className="space-y-3">
            <FlexBetween>
              <FlexItemsCenter>
                <div className="w-3 h-3 bg-theme-success-solid rounded-full mr-2"></div>
                <span className="text-sm text-theme-secondary">Active</span>
              </FlexItemsCenter>
              <span className="font-medium text-theme-success">{stats.active}</span>
            </FlexBetween>
            <FlexBetween>
              <FlexItemsCenter>
                <div className="w-3 h-3 bg-theme-warning-solid rounded-full mr-2"></div>
                <span className="text-sm text-theme-secondary">Suspended</span>
              </FlexItemsCenter>
              <span className="font-medium text-theme-warning">{stats.suspended}</span>
            </FlexBetween>
            <FlexBetween>
              <FlexItemsCenter>
                <div className="w-3 h-3 bg-theme-danger-solid rounded-full mr-2"></div>
                <span className="text-sm text-theme-secondary">Revoked</span>
              </FlexItemsCenter>
              <span className="font-medium text-theme-error">{stats.revoked}</span>
            </FlexBetween>
          </div>
        </Card>

        <Card className="p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Recently Created</h3>
          <div className="space-y-3">
            {recentWorkers.length === 0 ? (
              <p className="text-sm text-theme-secondary">No workers created recently</p>
            ) : (
              recentWorkers.map((worker) => (
                <FlexBetween key={worker.id}>
                  <div>
                    <div className="font-medium text-theme-primary text-sm">{worker.name}</div>
                    <div className="text-xs text-theme-secondary">{worker.account_name}</div>
                  </div>
                  <Badge
                    variant={worker.status === 'active' ? 'success' : 'secondary'}
                    size="sm"
                  >
                    {worker.status}
                  </Badge>
                </FlexBetween>
              ))
            )}
          </div>
        </Card>

        <Card className="p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Recently Active</h3>
          <div className="space-y-3">
            {activeWorkers.length === 0 ? (
              <p className="text-sm text-theme-secondary">No workers recently active</p>
            ) : (
              activeWorkers.map((worker) => (
                <FlexBetween key={worker.id}>
                  <div>
                    <div className="font-medium text-theme-primary text-sm">{worker.name}</div>
                    <div className="text-xs text-theme-secondary">
                      {worker.last_seen_at ?
                        `Last seen ${new Date(worker.last_seen_at).toLocaleDateString()}` :
                        'Never seen'
                      }
                    </div>
                  </div>
                  <div className="text-xs text-theme-primary">
                    {worker.request_count.toLocaleString()} requests
                  </div>
                </FlexBetween>
              ))
            )}
          </div>
        </Card>
      </div>

      {/* System Health Summary */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">System Health</h3>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="text-center p-4 bg-theme-surface rounded-lg">
            <div className="text-2xl font-bold text-theme-primary mb-1">{stats.recentlyActive}</div>
            <div className="text-sm text-theme-secondary">Online Now</div>
          </div>
          <div className="text-center p-4 bg-theme-surface rounded-lg">
            <div className="text-2xl font-bold text-theme-info mb-1">{stats.systemWorkers}</div>
            <div className="text-sm text-theme-secondary">System Workers</div>
          </div>
          <div className="text-center p-4 bg-theme-surface rounded-lg">
            <div className="text-2xl font-bold text-theme-warning mb-1">{stats.accountWorkers}</div>
            <div className="text-sm text-theme-secondary">Account Workers</div>
          </div>
          <div className="text-center p-4 bg-theme-surface rounded-lg">
            <div className="text-2xl font-bold text-theme-primary mb-1">
              {Math.round((stats.active / stats.total) * 100) || 0}%
            </div>
            <div className="text-sm text-theme-secondary">Uptime</div>
          </div>
        </div>
      </Card>
    </div>
  );
};
