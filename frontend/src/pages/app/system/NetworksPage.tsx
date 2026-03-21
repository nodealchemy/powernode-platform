import React, { useState, useCallback } from 'react';
import { Network } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { NetworkList, NetworkDetailModal, NetworkFormModal } from '@/features/system/components/networks';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderNetwork } from '@/features/system/types/system.types';

/**
 * NetworksPage - Main page for managing virtual networks
 *
 * Features:
 * - List networks with search and filters
 * - Create, view, edit, delete networks
 * - View network configuration (CIDR, DNS settings)
 * - Permission-based access control
 */
const NetworksPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.networks.create');
  const canDelete = hasPermission('system.networks.delete');

  // Modal state
  const [showFormModal, setShowFormModal] = useState(false);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [selectedNetworkId, setSelectedNetworkId] = useState<string | null>(null);
  const [editNetwork, setEditNetwork] = useState<SystemProviderNetwork | null>(null);
  const [networkToDelete, setNetworkToDelete] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [deleting, setDeleting] = useState(false);

  // Handler for viewing a network
  const handleView = useCallback((network: SystemProviderNetwork) => {
    setSelectedNetworkId(network.id);
    setShowDetailModal(true);
  }, []);

  // Handler for editing a network
  const handleEdit = useCallback((network: SystemProviderNetwork) => {
    setEditNetwork(network);
    setShowFormModal(true);
  }, []);

  // Handler for initiating delete
  const handleDeleteClick = useCallback((networkId: string) => {
    setNetworkToDelete(networkId);
    setShowDeleteConfirm(true);
  }, []);

  // Handler for confirming delete
  const handleDeleteConfirm = async () => {
    if (!networkToDelete) return;

    setDeleting(true);
    try {
      await systemApi.deleteNetwork(networkToDelete);
      addNotification({
        type: 'success',
        message: 'Network deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete network: ${errorMessage}`
      });
    } finally {
      setDeleting(false);
      setShowDeleteConfirm(false);
      setNetworkToDelete(null);
    }
  };

  // Handler for network saved
  const handleNetworkSaved = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    setEditNetwork(null);
  }, []);

  // Handler for opening create modal
  const handleCreate = useCallback(() => {
    setEditNetwork(null);
    setShowFormModal(true);
  }, []);

  // Handler for editing from detail modal
  const handleEditFromDetail = useCallback((network: SystemProviderNetwork) => {
    setShowDetailModal(false);
    setSelectedNetworkId(null);
    setEditNetwork(network);
    setShowFormModal(true);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Networks' }
  ];

  // Page actions
  const actions: PageAction[] = canCreate ? [
    {
      label: 'Create Network',
      icon: Network,
      onClick: handleCreate,
      variant: 'primary' as const
    }
  ] : [];

  return (
    <PageContainer
      title="Virtual Networks"
      description="Manage virtual networks for your infrastructure"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Network List */}
      <NetworkList
        key={refreshKey}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={canDelete ? handleDeleteClick : undefined}
        onCreate={canCreate ? handleCreate : undefined}
      />

      {/* Detail Modal */}
      <NetworkDetailModal
        networkId={selectedNetworkId}
        isOpen={showDetailModal}
        onClose={() => {
          setShowDetailModal(false);
          setSelectedNetworkId(null);
        }}
        onNetworkUpdated={() => setRefreshKey(prev => prev + 1)}
        onEdit={handleEditFromDetail}
      />

      {/* Create/Edit Modal */}
      <NetworkFormModal
        network={editNetwork}
        isOpen={showFormModal}
        onClose={() => {
          setShowFormModal(false);
          setEditNetwork(null);
        }}
        onNetworkSaved={handleNetworkSaved}
      />

      {/* Delete Confirmation Modal */}
      {showDeleteConfirm && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div
            className="fixed inset-0 bg-black/50 transition-opacity"
            onClick={() => setShowDeleteConfirm(false)}
          />
          <div className="flex min-h-full items-center justify-center p-4">
            <div className="relative w-full max-w-md bg-theme-surface rounded-lg shadow-xl">
              <div className="p-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-2">
                  Delete Network
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this network? This action cannot be undone.
                  All subnets and associated resources will also be removed.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowDeleteConfirm(false);
                      setNetworkToDelete(null);
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteConfirm}
                    disabled={deleting}
                  >
                    {deleting ? 'Deleting...' : 'Delete Network'}
                  </Button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </PageContainer>
  );
};

export default NetworksPage;
