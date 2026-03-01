import React, { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { RefreshCw, ArrowLeft } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useSwarmNodes } from '../hooks/useSwarmNodes';
import { useSwarmCluster } from '../hooks/useSwarmCluster';
import { NodeCard } from '../components/NodeCard';
import { NodeTopologyView } from '../components/NodeTopologyView';
import type { NodeFilters } from '../types';

export const SwarmNodesPage: React.FC = () => {
  const { clusterId } = useParams<{ clusterId: string }>();
  const navigate = useNavigate();
  const { cluster } = useSwarmCluster({ clusterId: clusterId || '' });
  const [filters, setFilters] = useState<NodeFilters>({});
  const [viewMode, setViewMode] = useState<'grid' | 'topology'>('grid');
  const { nodes, isLoading, error, refetch, updateNode, drainNode, removeNode } = useSwarmNodes({
    clusterId: clusterId || '',
    filters,
  });
  const { confirm, ConfirmationDialog } = useConfirmation();

  const handlePromote = async (nodeId: string) => {
    await updateNode(nodeId, { role: 'manager' });
  };

  const handleDemote = async (nodeId: string) => {
    await updateNode(nodeId, { role: 'worker' });
  };

  const handleDrain = (nodeId: string, hostname: string) => {
    confirm({
      title: 'Drain Node',
      message: `Are you sure you want to drain node "${hostname}"? All running tasks will be rescheduled to other nodes.`,
      confirmLabel: 'Drain',
      variant: 'warning',
      onConfirm: async () => { await drainNode(nodeId); },
    });
  };

  const handleRemove = (nodeId: string, hostname: string) => {
    confirm({
      title: 'Remove Node',
      message: `Are you sure you want to remove node "${hostname}" from the cluster?`,
      confirmLabel: 'Remove',
      variant: 'danger',
      onConfirm: async () => { await removeNode(nodeId); },
    });
  };

  const pageActions: PageAction[] = [
    { label: 'Back', onClick: () => navigate(`/app/devops/swarm/${clusterId}`), variant: 'secondary', icon: ArrowLeft },
    { label: 'Refresh', onClick: refetch, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Swarm Clusters', href: '/app/devops/swarm' },
    { label: cluster?.name || 'Cluster', href: `/app/devops/swarm/${clusterId}` },
    { label: 'Nodes' },
  ];

  if (isLoading) {
    return (
      <PageContainer title="Swarm Nodes" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center py-20">
          <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
          <span className="ml-3 text-theme-secondary">Loading nodes...</span>
        </div>
      </PageContainer>
    );
  }

  if (error) {
    return (
      <PageContainer title="Swarm Nodes" breadcrumbs={breadcrumbs}>
        <div className="text-center py-20">
          <p className="text-theme-error mb-4">{error}</p>
          <Button onClick={refetch} variant="secondary" size="sm">Retry</Button>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer title="Swarm Nodes" description={`${nodes.length} nodes in ${cluster?.name || 'cluster'}`} breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-4">
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <Button variant={viewMode === 'grid' ? 'primary' : 'ghost'} size="sm" onClick={() => setViewMode('grid')}>Grid</Button>
            <Button variant={viewMode === 'topology' ? 'primary' : 'ghost'} size="sm" onClick={() => setViewMode('topology')}>Topology</Button>
          </div>
          <select className="input-theme text-sm" value={filters.role || ''} onChange={(e) => setFilters((prev) => ({ ...prev, role: (e.target.value || undefined) as NodeFilters['role'] }))}>
            <option value="">All Roles</option>
            <option value="manager">Manager</option>
            <option value="worker">Worker</option>
          </select>
          <select className="input-theme text-sm" value={filters.status || ''} onChange={(e) => setFilters((prev) => ({ ...prev, status: (e.target.value || undefined) as NodeFilters['status'] }))}>
            <option value="">All Statuses</option>
            <option value="ready">Ready</option>
            <option value="down">Down</option>
            <option value="disconnected">Disconnected</option>
          </select>
        </div>

        {viewMode === 'topology' ? (
          <NodeTopologyView nodes={nodes} />
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {nodes.map((node) => (
              <NodeCard
                key={node.id}
                node={node}
                onPromote={node.role === 'worker' ? () => handlePromote(node.id) : undefined}
                onDemote={node.role === 'manager' ? () => handleDemote(node.id) : undefined}
                onDrain={node.availability !== 'drain' ? () => handleDrain(node.id, node.hostname) : undefined}
                onRemove={() => handleRemove(node.id, node.hostname)}
              />
            ))}
          </div>
        )}

        {nodes.length === 0 && (
          <div className="text-center py-12 text-theme-tertiary">No nodes found matching your filters.</div>
        )}
      </div>
      {ConfirmationDialog}
    </PageContainer>
  );
};
