import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { RefreshCw, Trash2, Download, Boxes, Server } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useKubernetesClusters } from '../hooks/useKubernetesClusters';
import { kubernetesApi } from '../services/kubernetesApi';
import type { ClusterEnvironment } from '../types';

interface KubernetesClustersPageProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const KubernetesClustersPage: React.FC<KubernetesClustersPageProps> = ({ onActionsReady }) => {
  const navigate = useNavigate();
  const [envFilter, setEnvFilter] = useState<ClusterEnvironment | undefined>();
  const { clusters, isLoading, error, refresh } = useKubernetesClusters(
    envFilter ? { environment: envFilter } : undefined,
  );
  const { confirm, ConfirmationDialog } = useConfirmation();

  // Cluster *creation* is implicit — operators provision by assigning
  // the k3s-server module to a NodeInstance. No "Add cluster" action
  // here; instead surface a "How to create" hint when the list is
  // empty. The PageAction "Refresh" stays available so operators can
  // poll for newly-bootstrapped clusters.
  useEffect(() => {
    onActionsReady?.([
      {
        label: 'Refresh',
        onClick: refresh,
        variant: 'secondary',
        icon: RefreshCw,
      },
    ]);
  }, [onActionsReady, refresh]);

  const handleDecommission = (id: string, name: string, nodeCount: number) => {
    confirm({
      title: 'Decommission Cluster',
      message: `Decommission "${name}"? This destroys the cluster row and removes ${nodeCount} member node(s) from Powernode bookkeeping. The underlying NodeInstances are NOT terminated.`,
      confirmLabel: 'Decommission',
      variant: 'danger',
      onConfirm: async () => {
        const result = await kubernetesApi.decommissionCluster(id);
        if (result.success) refresh();
      },
    });
  };

  const handleDownloadKubeconfig = async (id: string, name: string) => {
    const result = await kubernetesApi.getKubeconfig(id);
    if (!result.success || !result.data) return;

    // Trigger a browser download of the YAML.
    const blob = new Blob([result.data.kubeconfig], { type: 'text/yaml' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${name}-kubeconfig.yaml`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  };

  if (isLoading) {
    return (
      <div className="text-center py-12 text-theme-secondary">Loading clusters…</div>
    );
  }

  if (error) {
    return (
      <Card variant="default" padding="lg" className="text-center">
        <p className="text-theme-danger">{error}</p>
      </Card>
    );
  }

  return (
    <>
      <div className="space-y-6">
        <div className="flex items-center gap-4">
          <label className="text-sm font-medium text-theme-secondary">Environment:</label>
          <select
            className="input-theme"
            value={envFilter ?? ''}
            onChange={(e) => setEnvFilter((e.target.value || undefined) as ClusterEnvironment | undefined)}
          >
            <option value="">All</option>
            <option value="development">Development</option>
            <option value="staging">Staging</option>
            <option value="production">Production</option>
            <option value="custom">Custom</option>
          </select>
        </div>

        {clusters.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <Boxes className="w-12 h-12 mx-auto text-theme-tertiary mb-4" />
            <h3 className="text-lg font-semibold text-theme-primary mb-2">No Clusters Yet</h3>
            <p className="text-theme-secondary mb-4 max-w-xl mx-auto">
              Powernode auto-creates Kubernetes clusters when you assign the{' '}
              <code className="px-1 py-0.5 rounded bg-theme-surface text-xs">k3s-server</code>{' '}
              module to a NodeInstance. The agent installs k3s, captures the kubeconfig + tokens,
              and the cluster appears here within ~60 seconds.
            </p>
            <Button onClick={refresh} variant="primary" size="sm">
              <RefreshCw className="w-4 h-4 mr-2" /> Refresh
            </Button>
          </Card>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {clusters.map((cluster) => (
              <Card
                key={cluster.id}
                variant="default"
                hoverable
                clickable
                padding="lg"
                onClick={() => navigate(`/app/devops/kubernetes/${cluster.id}`)}
              >
                <div className="flex items-start justify-between mb-3">
                  <div className="flex-1 min-w-0">
                    <h3 className="text-lg font-semibold text-theme-primary truncate">{cluster.name}</h3>
                    <p className="text-sm text-theme-tertiary truncate">{cluster.api_endpoint}</p>
                  </div>
                  <span
                    className={`px-2 py-0.5 rounded text-xs font-medium ${kubernetesApi.getClusterStatusColor(cluster.status)}`}
                  >
                    {cluster.status}
                  </span>
                </div>

                <div className="flex items-center gap-2 mb-4 text-sm text-theme-secondary flex-wrap">
                  <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">
                    {cluster.flavor}
                  </span>
                  <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">
                    {cluster.environment}
                  </span>
                  <span className="inline-flex items-center gap-1">
                    <Server className="w-3.5 h-3.5" /> {cluster.node_count} nodes
                  </span>
                  {cluster.k8s_version && (
                    <span className="text-theme-tertiary text-xs truncate">{cluster.k8s_version}</span>
                  )}
                </div>

                <div className="flex items-center gap-2 border-t border-theme pt-3" onClick={(e) => e.stopPropagation()}>
                  <Button
                    size="xs"
                    variant="ghost"
                    onClick={() => handleDownloadKubeconfig(cluster.id, cluster.slug)}
                    disabled={!cluster.has_kubeconfig}
                    title={cluster.has_kubeconfig ? 'Download kubeconfig YAML' : 'Cluster is still bootstrapping'}
                  >
                    <Download className="w-3.5 h-3.5 mr-1" /> kubeconfig
                  </Button>
                  <Button
                    size="xs"
                    variant="danger"
                    onClick={() => handleDecommission(cluster.id, cluster.name, cluster.node_count)}
                  >
                    <Trash2 className="w-3.5 h-3.5 mr-1" /> Decommission
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>
      {ConfirmationDialog}
    </>
  );
};
