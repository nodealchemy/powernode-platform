import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { RefreshCw, ArrowLeft } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { useSwarmCluster } from '../hooks/useSwarmCluster';
import { swarmApi } from '../services/swarmApi';
import { SwarmStatsCards } from '../components/SwarmStatsCards';
import { ClusterStatusBadge } from '../components/ClusterStatusBadge';
import { HealthStatusGrid } from '../components/HealthStatusGrid';
import type { ClusterHealthSummary } from '../types';

export const ClusterDashboardPage: React.FC = () => {
  const { clusterId } = useParams<{ clusterId: string }>();
  const navigate = useNavigate();
  const { cluster, isLoading, error, refetch } = useSwarmCluster({ clusterId: clusterId || '' });
  const [health, setHealth] = useState<ClusterHealthSummary | null>(null);
  const [healthLoading, setHealthLoading] = useState(true);

  const fetchHealth = useCallback(async () => {
    if (!clusterId) return;
    setHealthLoading(true);
    const response = await swarmApi.getClusterHealth(clusterId);
    if (response.success && response.data) {
      setHealth(response.data.health);
    }
    setHealthLoading(false);
  }, [clusterId]);

  useEffect(() => {
    fetchHealth();
  }, [fetchHealth]);

  const handleRefresh = async () => {
    await Promise.all([refetch(), fetchHealth()]);
  };

  const handleSync = async () => {
    if (!clusterId) return;
    await swarmApi.syncCluster(clusterId);
    await handleRefresh();
  };

  const pageActions: PageAction[] = [
    { label: 'Back', onClick: () => navigate('/app/devops/swarm'), variant: 'secondary', icon: ArrowLeft },
    { label: 'Sync', onClick: handleSync, variant: 'primary', icon: RefreshCw },
    { label: 'Refresh', onClick: handleRefresh, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Swarm Clusters', href: '/app/devops/swarm' },
    { label: cluster?.name || 'Cluster' },
  ];

  if (isLoading) {
    return (
      <PageContainer title="Cluster Dashboard" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center py-20">
          <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
          <span className="ml-3 text-theme-secondary">Loading cluster...</span>
        </div>
      </PageContainer>
    );
  }

  if (error || !cluster) {
    return (
      <PageContainer title="Cluster Dashboard" breadcrumbs={breadcrumbs}>
        <div className="text-center py-20">
          <p className="text-theme-error mb-4">{error || 'Cluster not found'}</p>
          <Button onClick={() => navigate('/app/devops/swarm')} variant="secondary" size="sm">Back to Clusters</Button>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={cluster.name}
      description={`${cluster.environment} environment — ${cluster.api_endpoint}`}
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <div className="space-y-6">
        <div className="flex items-center gap-3">
          <ClusterStatusBadge status={cluster.status} />
          {cluster.last_synced_at && (
            <span className="text-xs text-theme-tertiary">
              Last synced: {new Date(cluster.last_synced_at).toLocaleString()}
            </span>
          )}
        </div>

        <SwarmStatsCards
          nodeCount={health?.node_health.total ?? 0}
          nodesReady={health?.node_health.ready ?? 0}
          serviceCount={health?.service_health.total ?? 0}
          servicesHealthy={health?.service_health.healthy ?? 0}
          avgHealth={health?.service_health.avg_health_percentage ?? 0}
          criticalEvents={health?.recent_events.critical ?? 0}
          warningEvents={health?.recent_events.warning ?? 0}
          isLoading={healthLoading}
        />

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Button variant="secondary" onClick={() => navigate(`/app/devops/swarm/${clusterId}/nodes`)} className="justify-start p-4">
            Manage Nodes ({health?.node_health.total ?? 0})
          </Button>
          <Button variant="secondary" onClick={() => navigate('/app/devops/swarm/services')} className="justify-start p-4">
            View Services ({health?.service_health.total ?? 0})
          </Button>
          <Button variant="secondary" onClick={() => navigate('/app/devops/swarm/stacks')} className="justify-start p-4">
            View Stacks
          </Button>
        </div>

        {health && <HealthStatusGrid healthData={[health]} isLoading={healthLoading} />}
      </div>
    </PageContainer>
  );
};
