import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Plus, RefreshCw } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useClusterContext } from '../hooks/useClusterContext';
import { useSwarmStacks } from '../hooks/useSwarmStacks';
import { ClusterSelector } from '../components/ClusterSelector';
import { StackDeployModal } from '../components/StackDeployModal';
import { StackCard } from '../components/StackCard';
import { ServiceScaleModal } from '../components/ServiceScaleModal';
import { ServiceRollbackModal } from '../components/ServiceRollbackModal';
import { swarmApi } from '../services/swarmApi';
import type { SwarmStack, SwarmServiceSummary } from '../types';

interface ExpandedData {
  details: SwarmStack | null;
  services: SwarmServiceSummary[];
  isLoading: boolean;
  error: string | null;
}

export const SwarmStacksPage: React.FC<{ onActionsReady?: (actions: PageAction[]) => void }> = ({ onActionsReady }) => {
  const { selectedClusterId } = useClusterContext();
  const { stacks, isLoading, error, refetch, createStack, deployStack, removeStack, deleteStack } = useSwarmStacks({
    clusterId: selectedClusterId || '',
    autoLoad: !!selectedClusterId,
  });

  const [showDeployModal, setShowDeployModal] = useState(false);
  const [expandedStackId, setExpandedStackId] = useState<string | null>(null);
  const expandedDataCache = useRef(new Map<string, ExpandedData>());
  const [, forceRender] = useState(0);

  const [scaleTarget, setScaleTarget] = useState<SwarmServiceSummary | null>(null);
  const [rollbackTarget, setRollbackTarget] = useState<SwarmServiceSummary | null>(null);

  const { confirm, ConfirmationDialog } = useConfirmation();

  // ─── Expand / collapse ────────────────────────────────────────────

  const handleToggleExpand = useCallback((stack: { id: string; name: string }) => {
    if (expandedStackId === stack.id) {
      setExpandedStackId(null);
      return;
    }
    setExpandedStackId(stack.id);

    const cached = expandedDataCache.current.get(stack.id);
    if (cached && !cached.error) return; // already fetched

    // Set loading state
    expandedDataCache.current.set(stack.id, { details: null, services: [], isLoading: true, error: null });
    forceRender((n) => n + 1);

    // Parallel fetch: stack details + services
    const clusterId = selectedClusterId!;
    Promise.all([
      swarmApi.getStack(clusterId, stack.id),
      swarmApi.getServices(clusterId, { stack_name: stack.name }),
    ]).then(([stackRes, servicesRes]) => {
      const entry: ExpandedData = {
        details: stackRes.success && stackRes.data ? stackRes.data.stack : null,
        services: servicesRes.success && servicesRes.data ? servicesRes.data.items : [],
        isLoading: false,
        error: (!stackRes.success ? stackRes.error : !servicesRes.success ? servicesRes.error : null) || null,
      };
      expandedDataCache.current.set(stack.id, entry);
      forceRender((n) => n + 1);
    });
  }, [expandedStackId, selectedClusterId]);

  // ─── Stack actions ────────────────────────────────────────────────

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

  // ─── Service actions (from expanded cards) ────────────────────────

  const handleScaleService = async (replicas: number) => {
    if (!scaleTarget || !selectedClusterId) return;
    await swarmApi.scaleService(selectedClusterId, scaleTarget.id, { replicas });
    // Invalidate cache for the parent stack and re-expand
    invalidateExpandedStack(scaleTarget.stack_id);
    setScaleTarget(null);
  };

  const handleRollbackService = async () => {
    if (!rollbackTarget || !selectedClusterId) return;
    await swarmApi.rollbackService(selectedClusterId, rollbackTarget.id);
    invalidateExpandedStack(rollbackTarget.stack_id);
    setRollbackTarget(null);
  };

  const invalidateExpandedStack = (stackId?: string) => {
    if (!stackId) return;
    expandedDataCache.current.delete(stackId);
    // Find stack name to re-trigger expand
    const stack = stacks.find((s) => s.id === stackId);
    if (stack && expandedStackId === stackId) {
      setExpandedStackId(null);
      // Re-expand after state settles
      setTimeout(() => handleToggleExpand({ id: stack.id, name: stack.name }), 0);
    }
  };

  // ─── Refresh ──────────────────────────────────────────────────────

  const handleRefresh = useCallback(() => {
    expandedDataCache.current.clear();
    setExpandedStackId(null);
    refetch();
  }, [refetch]);

  // ─── Render ───────────────────────────────────────────────────────

  const pageActions: PageAction[] = [
    { label: 'Deploy Stack', onClick: () => setShowDeployModal(true), variant: 'primary', icon: Plus },
    { label: 'Refresh', onClick: handleRefresh, variant: 'secondary', icon: RefreshCw },
  ];

  useEffect(() => {
    onActionsReady?.(pageActions);
  }, [onActionsReady, handleRefresh]);

  return (
    <>
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
            <Button onClick={handleRefresh} variant="secondary" size="sm">Retry</Button>
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
              <StackCard
                key={stack.id}
                stack={stack}
                isExpanded={expandedStackId === stack.id}
                expandedData={expandedDataCache.current.get(stack.id) || null}
                onToggleExpand={() => handleToggleExpand({ id: stack.id, name: stack.name })}
                onDeploy={() => handleRedeploy(stack.id)}
                onRemove={() => handleRemove(stack.id, stack.name)}
                onDelete={() => handleDelete(stack.id, stack.name)}
                onScaleService={setScaleTarget}
                onRollbackService={setRollbackTarget}
              />
            ))}
          </div>
        )}
      </div>

      <StackDeployModal isOpen={showDeployModal} onClose={() => setShowDeployModal(false)} onDeploy={handleDeploy} />

      {scaleTarget && (
        <ServiceScaleModal
          isOpen
          onClose={() => setScaleTarget(null)}
          serviceName={scaleTarget.service_name}
          currentReplicas={scaleTarget.desired_replicas}
          onScale={handleScaleService}
        />
      )}

      {rollbackTarget && (
        <ServiceRollbackModal
          isOpen
          onClose={() => setRollbackTarget(null)}
          serviceName={rollbackTarget.service_name}
          onRollback={handleRollbackService}
        />
      )}

      {ConfirmationDialog}
    </>
  );
};
