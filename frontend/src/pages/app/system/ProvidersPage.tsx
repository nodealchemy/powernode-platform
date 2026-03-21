import React, { useState, useCallback } from 'react';
import { Cloud } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ProviderList, ProviderDetailModal, ProviderFormModal } from '@/features/system/components/providers';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProvider } from '@/features/system/types/system.types';

/**
 * ProvidersPage - Main page for managing infrastructure providers
 *
 * Features:
 * - List providers with type filtering
 * - Create, view, edit, delete providers
 * - View provider regions and connections
 * - Permission-based access control
 */
const ProvidersPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.providers.create');
  const canDelete = hasPermission('system.providers.delete');

  // Modal state
  const [showFormModal, setShowFormModal] = useState(false);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [selectedProviderId, setSelectedProviderId] = useState<string | null>(null);
  const [editProvider, setEditProvider] = useState<SystemProvider | null>(null);
  const [providerToDelete, setProviderToDelete] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [deleting, setDeleting] = useState(false);

  // Handler for viewing a provider
  const handleView = useCallback((provider: SystemProvider) => {
    setSelectedProviderId(provider.id);
    setShowDetailModal(true);
  }, []);

  // Handler for editing a provider
  const handleEdit = useCallback((provider: SystemProvider) => {
    setEditProvider(provider);
    setShowFormModal(true);
  }, []);

  // Handler for initiating delete
  const handleDeleteClick = useCallback((providerId: string) => {
    setProviderToDelete(providerId);
    setShowDeleteConfirm(true);
  }, []);

  // Handler for confirming delete
  const handleDeleteConfirm = async () => {
    if (!providerToDelete) return;

    setDeleting(true);
    try {
      await systemApi.deleteProvider(providerToDelete);
      addNotification({
        type: 'success',
        message: 'Provider deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete provider: ${errorMessage}`
      });
    } finally {
      setDeleting(false);
      setShowDeleteConfirm(false);
      setProviderToDelete(null);
    }
  };

  // Handler for provider created/updated
  const handleProviderSaved = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    setEditProvider(null);
  }, []);

  // Handler for opening create modal
  const handleCreate = useCallback(() => {
    setEditProvider(null);
    setShowFormModal(true);
  }, []);

  // Handler for editing from detail modal
  const handleEditFromDetail = useCallback((provider: SystemProvider) => {
    setShowDetailModal(false);
    setSelectedProviderId(null);
    setEditProvider(provider);
    setShowFormModal(true);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Providers' }
  ];

  // Page actions
  const actions: PageAction[] = canCreate ? [
    {
      label: 'Add Provider',
      icon: Cloud,
      onClick: handleCreate,
      variant: 'primary' as const
    }
  ] : [];

  return (
    <PageContainer
      title="Infrastructure Providers"
      description="Manage cloud providers and their configuration"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Provider List */}
      <ProviderList
        key={refreshKey}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={canDelete ? handleDeleteClick : undefined}
        onCreate={canCreate ? handleCreate : undefined}
      />

      {/* Detail Modal */}
      <ProviderDetailModal
        providerId={selectedProviderId}
        isOpen={showDetailModal}
        onClose={() => {
          setShowDetailModal(false);
          setSelectedProviderId(null);
        }}
        onEdit={handleEditFromDetail}
      />

      {/* Create/Edit Modal */}
      <ProviderFormModal
        isOpen={showFormModal}
        onClose={() => {
          setShowFormModal(false);
          setEditProvider(null);
        }}
        onProviderSaved={handleProviderSaved}
        editProvider={editProvider}
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
                  Delete Provider
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this provider? This action cannot be undone.
                  All regions and connections associated with this provider will also be removed.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowDeleteConfirm(false);
                      setProviderToDelete(null);
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteConfirm}
                    disabled={deleting}
                  >
                    {deleting ? 'Deleting...' : 'Delete Provider'}
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

export default ProvidersPage;
