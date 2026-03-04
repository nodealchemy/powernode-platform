import React, { useState, useEffect } from 'react';
import { Plus, RefreshCw, Trash2 } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useClusterContext } from '../hooks/useClusterContext';
import { useSwarmNetworks } from '../hooks/useSwarmNetworks';
import { ClusterSelector } from '../components/ClusterSelector';
import { NetworkFormModal } from '../components/NetworkFormModal';
import type { NetworkFormData } from '../types';

export const SwarmNetworksPage: React.FC<{ onActionsReady?: (actions: PageAction[]) => void }> = ({ onActionsReady }) => {
  const { selectedClusterId } = useClusterContext();
  const { networks, isLoading, error, refetch, createNetwork, deleteNetwork } = useSwarmNetworks({
    clusterId: selectedClusterId || '',
    autoLoad: !!selectedClusterId,
  });
  const [showCreateModal, setShowCreateModal] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();

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

  const pageActions: PageAction[] = [
    { label: 'Create Network', onClick: () => setShowCreateModal(true), variant: 'primary', icon: Plus },
    { label: 'Refresh', onClick: refetch, variant: 'secondary', icon: RefreshCw },
  ];

  useEffect(() => {
    onActionsReady?.(pageActions);
  }, [onActionsReady, refetch]);

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
            <Button onClick={refetch} variant="secondary" size="sm">Retry</Button>
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
              <Card key={network.id} variant="default" padding="md">
                <div className="flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3">
                      <h3 className="text-base font-semibold text-theme-primary">{network.name}</h3>
                      <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">{network.driver}</span>
                      <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">{network.scope}</span>
                    </div>
                    <div className="flex items-center gap-3 mt-1 text-xs text-theme-tertiary">
                      {network.internal && <span>Internal</span>}
                      {network.attachable && <span>Attachable</span>}
                      {network.ingress && <span>Ingress</span>}
                      <span>Created: {new Date(network.created_at).toLocaleDateString()}</span>
                    </div>
                  </div>
                  <Button size="xs" variant="danger" onClick={() => handleDelete(network.id, network.name)} disabled={network.ingress}>
                    <Trash2 className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>

      <NetworkFormModal isOpen={showCreateModal} onClose={() => setShowCreateModal(false)} onSubmit={handleCreate} />
      {ConfirmationDialog}
    </>
  );
};
