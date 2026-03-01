import React, { useState, useEffect, useCallback } from 'react';
import { RefreshCw, Heart, Box, HardDrive, AlertTriangle } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useHostContext } from '../hooks/useHostContext';
import { useDockerHealth } from '../hooks/useDockerHealth';
import { useDockerEvents } from '../hooks/useDockerEvents';
import { dockerApi } from '../services/dockerApi';

const HostSelector: React.FC = () => {
  const { hosts, selectedHostId, selectHost, isLoading } = useHostContext();
  if (isLoading) return <span className="text-sm text-theme-tertiary">Loading hosts...</span>;
  if (hosts.length === 0) return <span className="text-sm text-theme-tertiary">No hosts configured</span>;
  const selected = hosts.find((h) => h.id === selectedHostId);
  return (
    <div className="flex items-center gap-3">
      <label className="text-sm font-medium text-theme-secondary">Host:</label>
      <select className="input-theme text-sm min-w-[200px]" value={selectedHostId || ''} onChange={(e) => selectHost(e.target.value || null)}>
        <option value="">Select host...</option>
        {hosts.map((h) => <option key={h.id} value={h.id}>{h.name} ({h.environment})</option>)}
      </select>
      {selected && (
        <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getHostStatusColor(selected.status)}`}>
          {selected.status}
        </span>
      )}
    </div>
  );
};

export const DockerHealthPage: React.FC = () => {
  const { selectedHostId } = useHostContext();
  const { health, isLoading, error, refresh } = useDockerHealth(selectedHostId);
  const { events, refresh: refreshEvents } = useDockerEvents(selectedHostId, 1, 10);
  const [autoRefresh, setAutoRefresh] = useState(true);

  const handleRefresh = useCallback(async () => {
    await Promise.all([refresh(), refreshEvents()]);
  }, [refresh, refreshEvents]);

  useEffect(() => {
    if (!autoRefresh || !selectedHostId) return;
    const interval = setInterval(handleRefresh, 30000);
    return () => clearInterval(interval);
  }, [autoRefresh, selectedHostId, handleRefresh]);

  const pageActions: PageAction[] = [
    { label: 'Refresh', onClick: handleRefresh, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Docker Hosts', href: '/app/devops/docker' },
    { label: 'Health' },
  ];

  return (
    <PageContainer title="Docker Health" description="Host health monitoring and diagnostics" breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-4">
        <div className="flex items-center justify-between flex-wrap gap-4">
          <HostSelector />
          <Button size="sm" variant={autoRefresh ? 'primary' : 'ghost'} onClick={() => setAutoRefresh(!autoRefresh)}>
            {autoRefresh ? 'Auto-refresh ON' : 'Auto-refresh OFF'}
          </Button>
        </div>

        {!selectedHostId ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">Select a host to view health data.</p>
          </Card>
        ) : isLoading && !health ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading health data...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={handleRefresh} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : health ? (
          <div className="space-y-6">
            <div className="flex items-center gap-3">
              <Heart className="w-5 h-5 text-theme-success" />
              <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getHostStatusColor(health.status)}`}>
                {health.status}
              </span>
              {autoRefresh && <span className="text-xs text-theme-tertiary">Auto-refresh: 30s</span>}
            </div>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <Card variant="default" padding="md">
                <div className="flex items-center gap-3 mb-2">
                  <Box className="w-6 h-6 text-theme-info" />
                  <span className="text-sm font-medium text-theme-primary">Containers</span>
                </div>
                <p className="text-2xl font-bold text-theme-primary">{health.container_health.total}</p>
                <div className="mt-1 text-xs text-theme-secondary space-y-0.5">
                  <div className="flex justify-between">
                    <span>Running</span>
                    <span className="text-theme-success font-medium">{health.container_health.running}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Stopped</span>
                    <span className="text-theme-tertiary font-medium">{health.container_health.stopped}</span>
                  </div>
                  {health.container_health.paused > 0 && (
                    <div className="flex justify-between">
                      <span>Paused</span>
                      <span className="text-theme-warning font-medium">{health.container_health.paused}</span>
                    </div>
                  )}
                </div>
              </Card>

              <Card variant="default" padding="md">
                <div className="flex items-center gap-3 mb-2">
                  <HardDrive className="w-6 h-6 text-theme-warning" />
                  <span className="text-sm font-medium text-theme-primary">Images</span>
                </div>
                <p className="text-2xl font-bold text-theme-primary">{health.image_stats.total}</p>
                {health.image_stats.dangling > 0 && (
                  <div className="mt-1 text-xs text-theme-warning">{health.image_stats.dangling} dangling</div>
                )}
              </Card>

              <Card variant="default" padding="md">
                <div className="flex items-center gap-3 mb-2">
                  <AlertTriangle className="w-6 h-6 text-theme-error" />
                  <span className="text-sm font-medium text-theme-primary">Events</span>
                </div>
                <p className="text-2xl font-bold text-theme-primary">{health.recent_events.unacknowledged}</p>
                <div className="mt-1 text-xs text-theme-secondary space-y-0.5">
                  <div className="flex justify-between">
                    <span>Critical</span>
                    <span className="text-theme-error font-medium">{health.recent_events.critical}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Warning</span>
                    <span className="text-theme-warning font-medium">{health.recent_events.warning}</span>
                  </div>
                </div>
              </Card>

              <Card variant="default" padding="md">
                <div className="flex items-center gap-3 mb-2">
                  <RefreshCw className="w-6 h-6 text-theme-success" />
                  <span className="text-sm font-medium text-theme-primary">Resources</span>
                </div>
                <div className="text-xs text-theme-secondary space-y-1">
                  {health.resource_usage.cpu_count != null && (
                    <div className="flex justify-between">
                      <span>CPUs</span>
                      <span className="text-theme-primary font-medium">{health.resource_usage.cpu_count}</span>
                    </div>
                  )}
                  {health.resource_usage.memory_bytes != null && health.resource_usage.memory_total != null && (
                    <div className="flex justify-between">
                      <span>Memory</span>
                      <span className="text-theme-primary font-medium">
                        {dockerApi.formatBytes(health.resource_usage.memory_bytes)} / {dockerApi.formatBytes(health.resource_usage.memory_total)}
                      </span>
                    </div>
                  )}
                  {health.resource_usage.storage_bytes != null && (
                    <div className="flex justify-between">
                      <span>Storage</span>
                      <span className="text-theme-primary font-medium">{dockerApi.formatBytes(health.resource_usage.storage_bytes)}</span>
                    </div>
                  )}
                </div>
              </Card>
            </div>

            {events.length > 0 && (
              <Card variant="default" padding="md">
                <h3 className="text-sm font-semibold text-theme-primary mb-3">Recent Events</h3>
                <div className="space-y-2">
                  {events.slice(0, 10).map((event) => (
                    <div key={event.id} className="flex items-center gap-3 text-sm">
                      <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getEventSeverityColor(event.severity)}`}>
                        {event.severity}
                      </span>
                      <span className="flex-1 text-theme-secondary truncate">{event.message}</span>
                      <span className="text-xs text-theme-tertiary whitespace-nowrap">
                        {new Date(event.created_at).toLocaleTimeString()}
                      </span>
                    </div>
                  ))}
                </div>
              </Card>
            )}
          </div>
        ) : null}
      </div>
    </PageContainer>
  );
};
