import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, RefreshCw, Play, Square, RotateCcw, Trash2 } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useDockerContainer } from '../hooks/useDockerContainer';
import { useContainerLogs } from '../hooks/useContainerLogs';
import { dockerApi } from '../services/dockerApi';
import type { ContainerStats } from '../types';

type TabId = 'info' | 'logs' | 'stats';

export const ContainerDetailPage: React.FC = () => {
  const { hostId, containerId } = useParams<{ hostId: string; containerId: string }>();
  const navigate = useNavigate();
  const { container, isLoading, error, refresh } = useDockerContainer(hostId || null, containerId || null);
  const { logs, isLoading: logsLoading, refresh: refreshLogs } = useContainerLogs(hostId || null, containerId || null, { tail: 200, timestamps: true });
  const [activeTab, setActiveTab] = useState<TabId>('info');
  const [stats, setStats] = useState<ContainerStats | null>(null);
  const [statsLoading, setStatsLoading] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();

  const fetchStats = useCallback(async () => {
    if (!hostId || !containerId) return;
    setStatsLoading(true);
    const response = await dockerApi.getContainerStats(hostId, containerId);
    if (response.success && response.data) {
      setStats(response.data.stats);
    }
    setStatsLoading(false);
  }, [hostId, containerId]);

  useEffect(() => {
    if (activeTab === 'stats') fetchStats();
  }, [activeTab, fetchStats]);

  const handleAction = (action: 'start' | 'stop' | 'restart' | 'delete') => {
    if (!hostId || !containerId) return;
    const execute = async () => {
      if (action === 'delete') {
        await dockerApi.deleteContainer(hostId, containerId);
        navigate(`/app/devops/docker/${hostId}/containers`);
        return;
      }
      const fn = { start: dockerApi.startContainer, stop: dockerApi.stopContainer, restart: dockerApi.restartContainer }[action];
      await fn(hostId, containerId);
      refresh();
    };
    if (action === 'delete') {
      confirm({ title: 'Delete Container', message: `Are you sure you want to delete "${container?.name}"? This action cannot be undone.`, confirmLabel: 'Delete', variant: 'danger', onConfirm: execute });
    } else if (action === 'stop') {
      confirm({ title: 'Stop Container', message: `Are you sure you want to stop "${container?.name}"?`, confirmLabel: 'Stop', variant: 'warning', onConfirm: execute });
    } else {
      execute();
    }
  };

  const pageActions: PageAction[] = [
    { label: 'Back', onClick: () => navigate(`/app/devops/docker/${hostId}/containers`), variant: 'secondary', icon: ArrowLeft },
    { label: 'Refresh', onClick: refresh, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Docker Hosts', href: '/app/devops/docker' },
    { label: 'Containers', href: `/app/devops/docker/${hostId}/containers` },
    { label: container?.name || 'Container' },
  ];

  if (isLoading) {
    return (
      <PageContainer title="Container Detail" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center py-20">
          <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
          <span className="ml-3 text-theme-secondary">Loading container...</span>
        </div>
      </PageContainer>
    );
  }

  if (error || !container) {
    return (
      <PageContainer title="Container Detail" breadcrumbs={breadcrumbs}>
        <div className="text-center py-20">
          <p className="text-theme-error mb-4">{error || 'Container not found'}</p>
          <Button onClick={() => navigate(`/app/devops/docker/${hostId}/containers`)} variant="secondary" size="sm">Back to Containers</Button>
        </div>
      </PageContainer>
    );
  }

  const tabs: { id: TabId; label: string }[] = [
    { id: 'info', label: 'Info' },
    { id: 'logs', label: 'Logs' },
    { id: 'stats', label: 'Stats' },
  ];

  return (
    <PageContainer title={container.name} description={container.image} breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-6">
        <div className="flex items-center gap-3 flex-wrap">
          <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getContainerStateColor(container.state)}`}>
            {container.state}
          </span>
          {container.status_text && <span className="text-sm text-theme-secondary">{container.status_text}</span>}
          <div className="flex gap-2 ml-auto">
            {container.state !== 'running' && (
              <Button size="sm" variant="primary" onClick={() => handleAction('start')}><Play className="w-4 h-4 mr-1" /> Start</Button>
            )}
            {container.state === 'running' && (
              <Button size="sm" variant="secondary" onClick={() => handleAction('stop')}><Square className="w-4 h-4 mr-1" /> Stop</Button>
            )}
            <Button size="sm" variant="secondary" onClick={() => handleAction('restart')}><RotateCcw className="w-4 h-4 mr-1" /> Restart</Button>
            <Button size="sm" variant="danger" onClick={() => handleAction('delete')}><Trash2 className="w-4 h-4 mr-1" /> Delete</Button>
          </div>
        </div>

        <div className="flex gap-1 border-b border-theme">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${activeTab === tab.id ? 'border-theme-brand text-theme-primary' : 'border-transparent text-theme-tertiary hover:text-theme-secondary'}`}
              onClick={() => setActiveTab(tab.id)}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {activeTab === 'info' && (
          <div className="space-y-4">
            <Card variant="default" padding="md">
              <h3 className="text-sm font-semibold text-theme-primary mb-3">Container Details</h3>
              <div className="grid grid-cols-2 gap-y-2 text-sm">
                <div><span className="text-theme-tertiary">ID:</span> <span className="text-theme-primary font-mono text-xs">{container.docker_container_id.slice(0, 12)}</span></div>
                <div><span className="text-theme-tertiary">Image:</span> <span className="text-theme-primary">{container.image}</span></div>
                <div><span className="text-theme-tertiary">Command:</span> <span className="text-theme-primary font-mono text-xs">{container.command || '—'}</span></div>
                <div><span className="text-theme-tertiary">Restart Policy:</span> <span className="text-theme-primary">{container.restart_policy || '—'}</span></div>
                <div><span className="text-theme-tertiary">Restart Count:</span> <span className="text-theme-primary">{container.restart_count}</span></div>
                <div><span className="text-theme-tertiary">Created:</span> <span className="text-theme-primary">{new Date(container.created_at).toLocaleString()}</span></div>
              </div>
            </Card>

            {container.ports.length > 0 && (
              <Card variant="default" padding="md">
                <h3 className="text-sm font-semibold text-theme-primary mb-3">Ports</h3>
                <div className="space-y-1">
                  {container.ports.map((p, i) => (
                    <div key={i} className="text-sm text-theme-secondary">
                      {p.ip || '0.0.0.0'}:{p.public_port || '—'} → {p.private_port}/{p.type}
                    </div>
                  ))}
                </div>
              </Card>
            )}

            {container.mounts.length > 0 && (
              <Card variant="default" padding="md">
                <h3 className="text-sm font-semibold text-theme-primary mb-3">Mounts</h3>
                <div className="space-y-1">
                  {container.mounts.map((m, i) => (
                    <div key={i} className="text-sm text-theme-secondary">
                      <span className="font-mono text-xs">{m.source}</span> → <span className="font-mono text-xs">{m.destination}</span> ({m.type}, {m.rw ? 'rw' : 'ro'})
                    </div>
                  ))}
                </div>
              </Card>
            )}
          </div>
        )}

        {activeTab === 'logs' && (
          <Card variant="default" padding="md">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-theme-primary">Container Logs</h3>
              <Button size="xs" variant="ghost" onClick={refreshLogs} loading={logsLoading}>{!logsLoading && <RefreshCw className="w-3.5 h-3.5" />}</Button>
            </div>
            <div className="bg-theme-surface rounded p-3 max-h-96 overflow-auto font-mono text-xs">
              {logs.length === 0 ? (
                <p className="text-theme-tertiary">No logs available.</p>
              ) : (
                logs.map((entry, i) => (
                  <div key={i} className={`py-0.5 ${entry.stream === 'stderr' ? 'text-theme-error' : 'text-theme-secondary'}`}>
                    <span className="text-theme-tertiary mr-2">{new Date(entry.timestamp).toLocaleTimeString()}</span>
                    {entry.message}
                  </div>
                ))
              )}
            </div>
          </Card>
        )}

        {activeTab === 'stats' && (
          <div className="space-y-4">
            <div className="flex justify-end">
              <Button size="xs" variant="ghost" onClick={fetchStats} loading={statsLoading}>{!statsLoading && <RefreshCw className="w-3.5 h-3.5 mr-1" />} Refresh Stats</Button>
            </div>
            {!stats ? (
              <Card variant="default" padding="lg" className="text-center">
                <p className="text-theme-secondary">{statsLoading ? 'Loading stats...' : 'No stats available. Container may not be running.'}</p>
              </Card>
            ) : (
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <Card variant="default" padding="md">
                  <p className="text-xs text-theme-tertiary mb-1">CPU</p>
                  <p className="text-xl font-bold text-theme-primary">{stats.cpu_percentage.toFixed(1)}%</p>
                </Card>
                <Card variant="default" padding="md">
                  <p className="text-xs text-theme-tertiary mb-1">Memory</p>
                  <p className="text-xl font-bold text-theme-primary">{stats.memory_percentage.toFixed(1)}%</p>
                  <p className="text-xs text-theme-secondary">{dockerApi.formatBytes(stats.memory_usage)} / {dockerApi.formatBytes(stats.memory_limit)}</p>
                </Card>
                <Card variant="default" padding="md">
                  <p className="text-xs text-theme-tertiary mb-1">Network I/O</p>
                  <p className="text-sm text-theme-primary">↓ {dockerApi.formatBytes(stats.network_rx)}</p>
                  <p className="text-sm text-theme-primary">↑ {dockerApi.formatBytes(stats.network_tx)}</p>
                </Card>
                <Card variant="default" padding="md">
                  <p className="text-xs text-theme-tertiary mb-1">Block I/O</p>
                  <p className="text-sm text-theme-primary">R: {dockerApi.formatBytes(stats.block_read)}</p>
                  <p className="text-sm text-theme-primary">W: {dockerApi.formatBytes(stats.block_write)}</p>
                </Card>
              </div>
            )}
          </div>
        )}
      </div>
      {ConfirmationDialog}
    </PageContainer>
  );
};
