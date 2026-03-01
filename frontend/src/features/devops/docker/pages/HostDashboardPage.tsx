import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { RefreshCw, ArrowLeft, Server, HardDrive, Box, Cpu } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useDockerHost } from '../hooks/useDockerHost';
import { dockerApi } from '../services/dockerApi';
import type { HostHealthSummary } from '../types';

export const HostDashboardPage: React.FC = () => {
  const { hostId } = useParams<{ hostId: string }>();
  const navigate = useNavigate();
  const { host, isLoading, error, refresh } = useDockerHost(hostId || null);
  const [health, setHealth] = useState<HostHealthSummary | null>(null);
  const [healthLoading, setHealthLoading] = useState(true);

  const fetchHealth = useCallback(async () => {
    if (!hostId) return;
    setHealthLoading(true);
    const response = await dockerApi.getHostHealth(hostId);
    if (response.success && response.data) {
      setHealth(response.data.health);
    }
    setHealthLoading(false);
  }, [hostId]);

  useEffect(() => {
    fetchHealth();
  }, [fetchHealth]);

  const handleRefresh = async () => {
    await Promise.all([refresh(), fetchHealth()]);
  };

  const handleSync = async () => {
    if (!hostId) return;
    await dockerApi.syncHost(hostId);
    await handleRefresh();
  };

  const pageActions: PageAction[] = [
    { label: 'Back', onClick: () => navigate('/app/devops/docker'), variant: 'secondary', icon: ArrowLeft },
    { label: 'Sync', onClick: handleSync, variant: 'primary', icon: RefreshCw },
    { label: 'Refresh', onClick: handleRefresh, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Docker Hosts', href: '/app/devops/docker' },
    { label: host?.name || 'Host' },
  ];

  if (isLoading) {
    return (
      <PageContainer title="Host Dashboard" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center py-20">
          <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
          <span className="ml-3 text-theme-secondary">Loading host...</span>
        </div>
      </PageContainer>
    );
  }

  if (error || !host) {
    return (
      <PageContainer title="Host Dashboard" breadcrumbs={breadcrumbs}>
        <div className="text-center py-20">
          <p className="text-theme-error mb-4">{error || 'Host not found'}</p>
          <Button onClick={() => navigate('/app/devops/docker')} variant="secondary" size="sm">Back to Hosts</Button>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={host.name}
      description={`${host.environment} environment — ${host.api_endpoint}`}
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <div className="space-y-6">
        <div className="flex items-center gap-3">
          <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getHostStatusColor(host.status)}`}>
            {host.status}
          </span>
          {host.last_synced_at && (
            <span className="text-xs text-theme-tertiary">
              Last synced: {new Date(host.last_synced_at).toLocaleString()}
            </span>
          )}
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Card variant="default" padding="md">
            <div className="flex items-center gap-3">
              <Box className="w-8 h-8 text-theme-info" />
              <div>
                <p className="text-2xl font-bold text-theme-primary">
                  {healthLoading ? '...' : health?.container_health.total ?? 0}
                </p>
                <p className="text-xs text-theme-tertiary">Containers</p>
              </div>
            </div>
            {health && (
              <div className="mt-2 text-xs text-theme-secondary">
                {health.container_health.running} running / {health.container_health.stopped} stopped
              </div>
            )}
          </Card>

          <Card variant="default" padding="md">
            <div className="flex items-center gap-3">
              <HardDrive className="w-8 h-8 text-theme-warning" />
              <div>
                <p className="text-2xl font-bold text-theme-primary">
                  {healthLoading ? '...' : health?.image_stats.total ?? 0}
                </p>
                <p className="text-xs text-theme-tertiary">Images</p>
              </div>
            </div>
            {health && health.image_stats.dangling > 0 && (
              <div className="mt-2 text-xs text-theme-warning">{health.image_stats.dangling} dangling</div>
            )}
          </Card>

          <Card variant="default" padding="md">
            <div className="flex items-center gap-3">
              <Cpu className="w-8 h-8 text-theme-success" />
              <div>
                <p className="text-2xl font-bold text-theme-primary">{host.cpu_count ?? '—'}</p>
                <p className="text-xs text-theme-tertiary">CPUs</p>
              </div>
            </div>
            {host.memory_bytes && (
              <div className="mt-2 text-xs text-theme-secondary">{dockerApi.formatBytes(host.memory_bytes)} RAM</div>
            )}
          </Card>

          <Card variant="default" padding="md">
            <div className="flex items-center gap-3">
              <Server className="w-8 h-8 text-theme-error" />
              <div>
                <p className="text-2xl font-bold text-theme-primary">
                  {healthLoading ? '...' : (health?.recent_events.critical ?? 0) + (health?.recent_events.warning ?? 0)}
                </p>
                <p className="text-xs text-theme-tertiary">Events</p>
              </div>
            </div>
            {health && (
              <div className="mt-2 text-xs text-theme-secondary">
                {health.recent_events.critical} critical / {health.recent_events.warning} warning
              </div>
            )}
          </Card>
        </div>

        <Card variant="default" padding="md">
          <h3 className="text-sm font-semibold text-theme-primary mb-3">Host Details</h3>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-y-2 text-sm">
            <div><span className="text-theme-tertiary">Docker:</span> <span className="text-theme-primary">{host.docker_version || '—'}</span></div>
            <div><span className="text-theme-tertiary">API:</span> <span className="text-theme-primary">{host.api_version}</span></div>
            <div><span className="text-theme-tertiary">OS:</span> <span className="text-theme-primary">{host.os_type || '—'}</span></div>
            <div><span className="text-theme-tertiary">Arch:</span> <span className="text-theme-primary">{host.architecture || '—'}</span></div>
            <div><span className="text-theme-tertiary">Kernel:</span> <span className="text-theme-primary">{host.kernel_version || '—'}</span></div>
            <div><span className="text-theme-tertiary">Storage:</span> <span className="text-theme-primary">{host.storage_bytes ? dockerApi.formatBytes(host.storage_bytes) : '—'}</span></div>
          </div>
        </Card>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Button variant="secondary" onClick={() => navigate(`/app/devops/docker/${hostId}/containers`)} className="justify-start p-4">
            Manage Containers ({health?.container_health.total ?? 0})
          </Button>
          <Button variant="secondary" onClick={() => navigate(`/app/devops/docker/${hostId}/images`)} className="justify-start p-4">
            View Images ({health?.image_stats.total ?? 0})
          </Button>
          <Button variant="secondary" onClick={() => navigate(`/app/devops/docker/${hostId}/health`)} className="justify-start p-4">
            Health Dashboard
          </Button>
        </div>
      </div>
    </PageContainer>
  );
};
