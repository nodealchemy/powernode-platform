import React, { useState, useEffect, useCallback } from 'react';
import { RefreshCw } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useSwarmClusters } from '../hooks/useSwarmClusters';
import { swarmApi } from '../services/swarmApi';
import { HealthStatusGrid } from '../components/HealthStatusGrid';
import type { ClusterHealthSummary } from '../types';

export const SwarmHealthPage: React.FC<{ onActionsReady?: (actions: PageAction[]) => void }> = ({ onActionsReady }) => {
  const { clusters } = useSwarmClusters();
  const [healthData, setHealthData] = useState<ClusterHealthSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(true);

  const fetchAllHealth = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    const results = await Promise.all(
      clusters.map(async (cluster) => {
        const response = await swarmApi.getClusterHealth(cluster.id);
        if (response.success && response.data) {
          return response.data.health;
        }
        return null;
      })
    );

    const validResults = results.filter((r): r is ClusterHealthSummary => r !== null);
    setHealthData(validResults);

    if (validResults.length === 0 && clusters.length > 0) {
      setError('Failed to fetch health data from any cluster');
    }

    setIsLoading(false);
  }, [clusters]);

  useEffect(() => {
    if (clusters.length > 0) {
      fetchAllHealth();
    } else {
      setIsLoading(false);
    }
  }, [clusters, fetchAllHealth]);

  useEffect(() => {
    if (!autoRefresh || clusters.length === 0) return;

    const interval = setInterval(fetchAllHealth, 30000);
    return () => clearInterval(interval);
  }, [autoRefresh, clusters.length, fetchAllHealth]);

  const pageActions: PageAction[] = [
    { label: 'Refresh', onClick: fetchAllHealth, variant: 'secondary', icon: RefreshCw },
  ];

  useEffect(() => {
    onActionsReady?.(pageActions);
  }, [onActionsReady, fetchAllHealth]);

  return (
    <>
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <span className="text-sm text-theme-secondary">{clusters.length} cluster(s)</span>
            {autoRefresh && <span className="text-xs text-theme-tertiary">Auto-refresh: 30s</span>}
          </div>
          <Button
            size="sm"
            variant={autoRefresh ? 'primary' : 'ghost'}
            onClick={() => setAutoRefresh(!autoRefresh)}
          >
            {autoRefresh ? 'Auto-refresh ON' : 'Auto-refresh OFF'}
          </Button>
        </div>

        {isLoading && healthData.length === 0 ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading health data...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={fetchAllHealth} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : clusters.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">No clusters configured. Add a cluster to start monitoring.</p>
          </Card>
        ) : (
          <HealthStatusGrid healthData={healthData} clusterNames={clusters} isLoading={isLoading} />
        )}
      </div>
    </>
  );
};
