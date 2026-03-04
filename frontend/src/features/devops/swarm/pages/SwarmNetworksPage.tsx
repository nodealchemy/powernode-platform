import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Plus, RefreshCw } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useClusterContext } from '../hooks/useClusterContext';
import { useSwarmNetworks } from '../hooks/useSwarmNetworks';
import { ClusterSelector } from '../components/ClusterSelector';
import { NetworkFormModal } from '../components/NetworkFormModal';
import { NetworkCard } from '../components/NetworkCard';
import type { NetworkExpandedData } from '../components/NetworkCard';
import { swarmApi } from '../services/swarmApi';
import type { NetworkFormData } from '../types';

export const SwarmNetworksPage: React.FC<{ onActionsReady?: (actions: PageAction[]) => void }> = ({ onActionsReady }) => {
  const { selectedClusterId } = useClusterContext();
  const { networks, isLoading, error, refetch, createNetwork, deleteNetwork } = useSwarmNetworks({
    clusterId: selectedClusterId || '',
    autoLoad: !!selectedClusterId,
  });
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [expandedNetworkId, setExpandedNetworkId] = useState<string | null>(null);
  const expandedDataCache = useRef(new Map<string, NetworkExpandedData>());
  const [, forceRender] = useState(0);
  const { confirm, ConfirmationDialog } = useConfirmation();

  // ─── Expand / collapse ────────────────────────────────────────────

  const handleToggleExpand = useCallback((networkId: string) => {
    if (expandedNetworkId === networkId) {
      setExpandedNetworkId(null);
      return;
    }
    setExpandedNetworkId(networkId);

    const cached = expandedDataCache.current.get(networkId);
    if (cached && !cached.error) return;

    expandedDataCache.current.set(networkId, { details: null, isLoading: true, error: null });
    forceRender((n) => n + 1);

    const clusterId = selectedClusterId!;
    swarmApi.getNetwork(clusterId, networkId).then((res) => {
      const entry: NetworkExpandedData = {
        details: res.success && res.data ? res.data.network : null,
        isLoading: false,
        error: !res.success ? (res.error || 'Failed to fetch network details') : null,
      };
      expandedDataCache.current.set(networkId, entry);
      forceRender((n) => n + 1);
    });
  }, [expandedNetworkId, selectedClusterId]);

  // ─── Actions ──────────────────────────────────────────────────────

  const handleCreate = async (data: NetworkFormData) => {
    const result = await createNetwork(data);
    if (result) {
      setShowCreateModal(false);
    }
  };

  const handleDelete = (networkId: string, networkName: string) => {
    confirm({
      title: 'Delete Network',
      message: `Are you sure you want to delete network "${networkName}"?`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => { await deleteNetwork(networkId); },
    });
  };

  // ─── Refresh ──────────────────────────────────────────────────────

  const handleRefresh = useCallback(() => {
    expandedDataCache.current.clear();
    setExpandedNetworkId(null);
    refetch();
  }, [refetch]);

  // ─── Page actions ─────────────────────────────────────────────────

  const pageActions: PageAction[] = [
    { label: 'Create Network', onClick: () => setShowCreateModal(true), variant: 'primary', icon: Plus },
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
            <p className="text-theme-secondary">Select a cluster to view networks.</p>
          </Card>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading networks...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={handleRefresh} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : networks.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary mb-4">No networks found.</p>
            <Button onClick={() => setShowCreateModal(true)} variant="primary" size="sm">
              <Plus className="w-4 h-4 mr-2" /> Create Network
            </Button>
          </Card>
        ) : (
          <div className="space-y-3">
            {networks.map((network) => (
              <NetworkCard
                key={network.id}
                network={network}
                isExpanded={expandedNetworkId === network.id}
                expandedData={expandedDataCache.current.get(network.id) || null}
                onToggleExpand={() => handleToggleExpand(network.id)}
                onDelete={() => handleDelete(network.id, network.name)}
              />
            ))}
          </div>
        )}
      </div>

      <NetworkFormModal isOpen={showCreateModal} onClose={() => setShowCreateModal(false)} onSubmit={handleCreate} />
      {ConfirmationDialog}
    </>
  );
};
