import React, { useState } from 'react';
import { Plus, RefreshCw, Trash2, Rocket, XCircle } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useClusterContext } from '../hooks/useClusterContext';
import { useSwarmStacks } from '../hooks/useSwarmStacks';
import { ClusterSelector } from '../components/ClusterSelector';
import { StackDeployModal } from '../components/StackDeployModal';
import { swarmApi } from '../services/swarmApi';

export const SwarmStacksPage: React.FC = () => {
  const { selectedClusterId } = useClusterContext();
  const { stacks, isLoading, error, refetch, createStack, deployStack, removeStack, deleteStack } = useSwarmStacks({
    clusterId: selectedClusterId || '',
    autoLoad: !!selectedClusterId,
  });
  const [showDeployModal, setShowDeployModal] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();

  const handleDeploy = async (name: string, composeFile: string) => {
    const stack = await createStack({ name, compose_file: composeFile });
    if (stack) {
      await deployStack(stack.id);
      setShowDeployModal(false);
    }
  };

  const handleRedeploy = async (stackId: string) => {
    await deployStack(stackId);
  };

  const handleRemove = (stackId: string, stackName: string) => {
    confirm({
      title: 'Remove Stack',
      message: `Are you sure you want to remove stack "${stackName}"? All services in this stack will be stopped.`,
      confirmLabel: 'Remove',
      variant: 'warning',
      onConfirm: async () => { await removeStack(stackId); },
    });
  };

  const handleDelete = (stackId: string, stackName: string) => {
    confirm({
      title: 'Delete Stack',
      message: `Are you sure you want to permanently delete stack "${stackName}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => { await deleteStack(stackId); },
    });
  };

  const pageActions: PageAction[] = [
    { label: 'Deploy Stack', onClick: () => setShowDeployModal(true), variant: 'primary', icon: Plus },
    { label: 'Refresh', onClick: refetch, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Swarm Clusters', href: '/app/devops/swarm' },
    { label: 'Stacks' },
  ];

  return (
    <PageContainer title="Swarm Stacks" description="Deploy and manage Docker Compose stacks" breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-4">
        <ClusterSelector />

        {!selectedClusterId ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">Select a cluster to view stacks.</p>
          </Card>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading stacks...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={refetch} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : stacks.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary mb-4">No stacks deployed.</p>
            <Button onClick={() => setShowDeployModal(true)} variant="primary" size="sm">
              <Plus className="w-4 h-4 mr-2" /> Deploy Stack
            </Button>
          </Card>
        ) : (
          <div className="space-y-3">
            {stacks.map((stack) => (
              <Card key={stack.id} variant="default" padding="md">
                <div className="flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3">
                      <h3 className="text-base font-semibold text-theme-primary">{stack.name}</h3>
                      <span className={`px-2 py-0.5 rounded text-xs font-medium ${swarmApi.getStackStatusColor(stack.status)}`}>
                        {stack.status}
                      </span>
                    </div>
                    <div className="flex items-center gap-4 mt-1 text-xs text-theme-tertiary">
                      <span>{stack.service_count} services</span>
                      <span>{stack.deploy_count} deploys</span>
                      {stack.last_deployed_at && <span>Last: {new Date(stack.last_deployed_at).toLocaleString()}</span>}
                    </div>
                  </div>
                  <div className="flex items-center gap-1">
                    <Button size="xs" variant="ghost" onClick={() => handleRedeploy(stack.id)} title="Deploy">
                      <Rocket className="w-3.5 h-3.5" />
                    </Button>
                    <Button size="xs" variant="ghost" onClick={() => handleRemove(stack.id, stack.name)} title="Remove">
                      <XCircle className="w-3.5 h-3.5" />
                    </Button>
                    <Button size="xs" variant="danger" onClick={() => handleDelete(stack.id, stack.name)} title="Delete">
                      <Trash2 className="w-3.5 h-3.5" />
                    </Button>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>

      <StackDeployModal isOpen={showDeployModal} onClose={() => setShowDeployModal(false)} onDeploy={handleDeploy} />
      {ConfirmationDialog}
    </PageContainer>
  );
};
