import React, { useState } from 'react';
import { RefreshCw } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useClusterContext } from '../hooks/useClusterContext';
import { useSwarmDeployments } from '../hooks/useSwarmDeployments';
import { ClusterSelector } from '../components/ClusterSelector';
import { DeploymentTimeline } from '../components/DeploymentTimeline';
import type { DeploymentFilters, DeploymentType, DeploymentStatus } from '../types';

export const SwarmDeploymentsPage: React.FC = () => {
  const { selectedClusterId } = useClusterContext();
  const [filters, setFilters] = useState<DeploymentFilters>({});
  const { deployments, pagination, isLoading, error, refetch, loadMore, cancelDeployment } = useSwarmDeployments({
    clusterId: selectedClusterId || '',
    filters,
    autoLoad: !!selectedClusterId,
  });
  const { confirm, ConfirmationDialog } = useConfirmation();

  const handleCancel = (deploymentId: string) => {
    confirm({
      title: 'Cancel Deployment',
      message: 'Are you sure you want to cancel this deployment? Any in-progress changes may be left in an incomplete state.',
      confirmLabel: 'Cancel Deployment',
      variant: 'warning',
      onConfirm: async () => { await cancelDeployment(deploymentId); },
    });
  };

  const pageActions: PageAction[] = [
    { label: 'Refresh', onClick: refetch, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Swarm Clusters', href: '/app/devops/swarm' },
    { label: 'Deployments' },
  ];

  return (
    <PageContainer title="Deployments" description="Swarm deployment history and timeline" breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-4">
        <div className="flex items-center gap-4">
          <ClusterSelector />
          <select
            className="input-theme text-sm"
            value={filters.deployment_type || ''}
            onChange={(e) => setFilters((prev) => ({ ...prev, deployment_type: (e.target.value || undefined) as DeploymentType | undefined }))}
          >
            <option value="">All Types</option>
            <option value="deploy">Deploy</option>
            <option value="update">Update</option>
            <option value="scale">Scale</option>
            <option value="rollback">Rollback</option>
            <option value="remove">Remove</option>
            <option value="stack_deploy">Stack Deploy</option>
            <option value="stack_remove">Stack Remove</option>
          </select>
          <select
            className="input-theme text-sm"
            value={filters.status || ''}
            onChange={(e) => setFilters((prev) => ({ ...prev, status: (e.target.value || undefined) as DeploymentStatus | undefined }))}
          >
            <option value="">All Statuses</option>
            <option value="pending">Pending</option>
            <option value="running">Running</option>
            <option value="completed">Completed</option>
            <option value="failed">Failed</option>
            <option value="cancelled">Cancelled</option>
          </select>
        </div>

        {!selectedClusterId ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">Select a cluster to view deployments.</p>
          </Card>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading deployments...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={refetch} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : deployments.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">No deployments found.</p>
          </Card>
        ) : (
          <>
            <DeploymentTimeline deployments={deployments} onCancel={handleCancel} />
            {pagination && pagination.current_page < pagination.total_pages && (
              <div className="text-center pt-4">
                <Button variant="secondary" size="sm" onClick={loadMore}>Load More</Button>
              </div>
            )}
          </>
        )}
      </div>
      {ConfirmationDialog}
    </PageContainer>
  );
};
