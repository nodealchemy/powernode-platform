import React from 'react';
import {
  Activity,
  Cpu,
  Database,
  HardDrive,
  MemoryStick,
  RefreshCw,
  Server,
  Wifi
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Progress } from '@/shared/components/ui/Progress';
import { Loading } from '@/shared/components/ui/Loading';
import { ResourceUtilization } from '@/shared/types/monitoring';

interface ResourceUtilizationChartProps {
  resourceData: ResourceUtilization | null;
  isLoading: boolean;
  onRefresh: () => void;
}

export const ResourceUtilizationChart: React.FC<ResourceUtilizationChartProps> = ({
  resourceData,
  isLoading,
  onRefresh
}) => {
  const getUtilizationColor = (percentage: number) => {
    if (percentage >= 90) return 'text-theme-error';
    if (percentage >= 75) return 'text-theme-warning';
    if (percentage >= 50) return 'text-theme-info';
    return 'text-theme-success';
  };

  if (isLoading && !resourceData) {
    return (
      <Card>
        <CardHeader
          title="Resource Utilization"
          icon={<Server className="h-5 w-5" />}
        />
        <CardContent className="flex items-center justify-center py-8">
          <Loading size="lg" message="Loading resource data..." />
        </CardContent>
      </Card>
    );
  }

  if (!resourceData) {
    return (
      <Card>
        <CardHeader
          title="Resource Utilization"
          icon={<Server className="h-5 w-5" />}
        />
        <CardContent className="py-8 text-center">
          <Server className="h-12 w-12 text-theme-muted mx-auto mb-4" />
          <p className="text-theme-muted">No resource data available</p>
          <Button onClick={onRefresh} variant="outline" size="sm" className="mt-4">
            <RefreshCw className="h-4 w-4 mr-2" />
            Load Resource Data
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader
        title="Resource Utilization"
        icon={<Server className="h-5 w-5" />}
        action={
          <Button
            onClick={onRefresh}
            variant="ghost"
            size="sm"
            disabled={isLoading}
          >
            <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
          </Button>
        }
      />
      <CardContent className="space-y-6">
        {/* System Resources */}
        <div className="space-y-4">
          <h4 className="text-sm font-medium text-theme-primary flex items-center gap-2">
            <Activity className="h-4 w-4" />
            System Resources
          </h4>
          
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Cpu className="h-4 w-4 text-theme-muted" />
                <span className="text-sm text-theme-primary">CPU Usage</span>
              </div>
              <span className={`text-sm font-medium ${getUtilizationColor(resourceData.system.cpu_usage)}`}>
                {resourceData.system.cpu_usage.toFixed(1)}%
              </span>
            </div>
            <Progress value={resourceData.system.cpu_usage} className="h-2" />

            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <MemoryStick className="h-4 w-4 text-theme-muted" />
                <span className="text-sm text-theme-primary">Memory Usage</span>
              </div>
              <span className={`text-sm font-medium ${getUtilizationColor(resourceData.system.memory_usage)}`}>
                {resourceData.system.memory_usage.toFixed(1)}%
              </span>
            </div>
            <Progress value={resourceData.system.memory_usage} className="h-2" />

            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <HardDrive className="h-4 w-4 text-theme-muted" />
                <span className="text-sm text-theme-primary">Disk Usage</span>
              </div>
              <span className={`text-sm font-medium ${getUtilizationColor(resourceData.system.disk_usage)}`}>
                {resourceData.system.disk_usage.toFixed(1)}%
              </span>
            </div>
            <Progress value={resourceData.system.disk_usage} className="h-2" />

            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Wifi className="h-4 w-4 text-theme-muted" />
                <span className="text-sm text-theme-primary">Network Usage</span>
              </div>
              <span className={`text-sm font-medium ${getUtilizationColor(resourceData.system.network_usage)}`}>
                {resourceData.system.network_usage.toFixed(1)}%
              </span>
            </div>
            <Progress value={resourceData.system.network_usage} className="h-2" />
          </div>
        </div>

        {/* Database Resources */}
        <div className="space-y-4">
          <h4 className="text-sm font-medium text-theme-primary flex items-center gap-2">
            <Database className="h-4 w-4" />
            Database Resources
          </h4>
          
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-2">
              <h5 className="text-xs font-medium text-theme-muted">Connection Pool</h5>
              <div className="space-y-1">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-theme-muted">Used</span>
                  <span className="font-medium">
                    {resourceData.database.connection_pool.used} / {resourceData.database.connection_pool.size}
                  </span>
                </div>
                <Progress 
                  value={(resourceData.database.connection_pool.used / resourceData.database.connection_pool.size) * 100} 
                  className="h-1.5" 
                />
              </div>
            </div>

            <div className="space-y-2">
              <h5 className="text-xs font-medium text-theme-muted">Storage</h5>
              <div className="space-y-1">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-theme-muted">Used</span>
                  <span className="font-medium">
                    {((resourceData.database.storage_usage.used_size / resourceData.database.storage_usage.total_size) * 100).toFixed(1)}%
                  </span>
                </div>
                <Progress 
                  value={(resourceData.database.storage_usage.used_size / resourceData.database.storage_usage.total_size) * 100} 
                  className="h-1.5" 
                />
              </div>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-4 text-xs">
            <div className="text-center p-2 bg-theme-surface rounded">
              <div className="font-medium text-theme-primary">
                {resourceData.database.query_performance.avg_query_time.toFixed(1)}ms
              </div>
              <div className="text-theme-muted">Avg Query Time</div>
            </div>
            <div className="text-center p-2 bg-theme-surface rounded">
              <div className="font-medium text-theme-warning">
                {resourceData.database.query_performance.slow_queries}
              </div>
              <div className="text-theme-muted">Slow Queries</div>
            </div>
            <div className="text-center p-2 bg-theme-surface rounded">
              <div className="font-medium text-theme-error">
                {resourceData.database.query_performance.deadlocks}
              </div>
              <div className="text-theme-muted">Deadlocks</div>
            </div>
          </div>
        </div>

        {/* Redis Resources */}
        <div className="space-y-4">
          <h4 className="text-sm font-medium text-theme-primary">Redis Cache</h4>
          
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-muted">Memory Usage</span>
                <span className="font-medium">
                  {((resourceData.redis.memory_usage.used / resourceData.redis.memory_usage.limit) * 100).toFixed(1)}%
                </span>
              </div>
              <Progress 
                value={(resourceData.redis.memory_usage.used / resourceData.redis.memory_usage.limit) * 100} 
                className="h-2" 
              />
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-muted">Hit Rate</span>
                <span className={`font-medium ${resourceData.redis.hit_rate >= 95 ? 'text-theme-success' : resourceData.redis.hit_rate >= 85 ? 'text-theme-warning' : 'text-theme-error'}`}>
                  {resourceData.redis.hit_rate.toFixed(1)}%
                </span>
              </div>
              <Progress value={resourceData.redis.hit_rate} className="h-2" />
            </div>
          </div>

          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-muted">Active Connections</span>
            <span className="font-medium">{resourceData.redis.connection_count}</span>
          </div>
        </div>

        {/* Sidekiq Workers */}
        <div className="space-y-4">
          <h4 className="text-sm font-medium text-theme-primary">Background Workers</h4>
          
          <div className="grid grid-cols-3 gap-4 text-sm">
            <div className="text-center p-2 bg-theme-surface rounded">
              <div className="font-medium text-theme-success">
                {resourceData.sidekiq.worker_utilization.busy}
              </div>
              <div className="text-xs text-theme-muted">Busy</div>
            </div>
            <div className="text-center p-2 bg-theme-surface rounded">
              <div className="font-medium text-theme-info">
                {resourceData.sidekiq.worker_utilization.idle}
              </div>
              <div className="text-xs text-theme-muted">Idle</div>
            </div>
            <div className="text-center p-2 bg-theme-surface rounded">
              <div className="font-medium text-theme-error">
                {resourceData.sidekiq.failed_jobs}
              </div>
              <div className="text-xs text-theme-muted">Failed Jobs</div>
            </div>
          </div>

          {Object.keys(resourceData.sidekiq.queue_sizes).length > 0 && (
            <div className="space-y-2">
              <h5 className="text-xs font-medium text-theme-muted">Queue Sizes</h5>
              <div className="grid grid-cols-2 gap-2">
                {Object.entries(resourceData.sidekiq.queue_sizes).slice(0, 4).map(([queue, size]) => (
                  <div key={queue} className="flex items-center justify-between text-xs">
                    <span className="text-theme-muted truncate">{queue}</span>
                    <span className="font-medium">{size}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* ActionCable */}
        <div className="space-y-4">
          <h4 className="text-sm font-medium text-theme-primary">WebSocket Connections</h4>
          
          <div className="grid grid-cols-3 gap-4 text-sm">
            <div className="text-center p-2 bg-theme-surface rounded">
              <div className="font-medium text-theme-primary">
                {resourceData.actioncable.connection_count}
              </div>
              <div className="text-xs text-theme-muted">Connections</div>
            </div>
            <div className="text-center p-2 bg-theme-surface rounded">
              <div className="font-medium text-theme-info">
                {resourceData.actioncable.subscription_count}
              </div>
              <div className="text-xs text-theme-muted">Subscriptions</div>
            </div>
            <div className="text-center p-2 bg-theme-surface rounded">
              <div className="font-medium text-theme-success">
                {resourceData.actioncable.message_throughput.toFixed(1)}/s
              </div>
              <div className="text-xs text-theme-muted">Messages</div>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};