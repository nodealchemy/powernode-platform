import React, { useState, useCallback } from 'react';
import { HardDrive } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { VolumeList, VolumeDetailModal, VolumeFormModal, VolumeAttachModal } from '@/features/system/components/volumes';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderVolume } from '@/features/system/types/system.types';

/**
 * VolumesPage - Main page for managing storage volumes
 *
 * Features:
 * - List volumes with search and filters
 * - Create, view, edit, delete volumes
 * - Attach/detach volumes to instances
 * - Create volume snapshots
 * - Permission-based access control
 */
const VolumesPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.volumes.create');
  const canDelete = hasPermission('system.volumes.delete');

  // Modal state
  const [showFormModal, setShowFormModal] = useState(false);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [showAttachModal, setShowAttachModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [selectedVolumeId, setSelectedVolumeId] = useState<string | null>(null);
  const [editVolume, setEditVolume] = useState<SystemProviderVolume | null>(null);
  const [attachVolume, setAttachVolume] = useState<SystemProviderVolume | null>(null);
  const [volumeToDelete, setVolumeToDelete] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [deleting, setDeleting] = useState(false);
  const [_detaching, setDetaching] = useState(false);

  // Handler for viewing a volume
  const handleView = useCallback((volume: SystemProviderVolume) => {
    setSelectedVolumeId(volume.id);
    setShowDetailModal(true);
  }, []);

  // Handler for editing a volume
  const handleEdit = useCallback((volume: SystemProviderVolume) => {
    setEditVolume(volume);
    setShowFormModal(true);
  }, []);

  // Handler for initiating delete
  const handleDeleteClick = useCallback((volumeId: string) => {
    setVolumeToDelete(volumeId);
    setShowDeleteConfirm(true);
  }, []);

  // Handler for confirming delete
  const handleDeleteConfirm = async () => {
    if (!volumeToDelete) return;

    setDeleting(true);
    try {
      await systemApi.deleteVolume(volumeToDelete);
      addNotification({
        type: 'success',
        message: 'Volume deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete volume: ${errorMessage}`
      });
    } finally {
      setDeleting(false);
      setShowDeleteConfirm(false);
      setVolumeToDelete(null);
    }
  };

  // Handler for volume saved
  const handleVolumeSaved = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    setEditVolume(null);
  }, []);

  // Handler for opening create modal
  const handleCreate = useCallback(() => {
    setEditVolume(null);
    setShowFormModal(true);
  }, []);

  // Handler for attach
  const handleAttach = useCallback((volume: SystemProviderVolume) => {
    setAttachVolume(volume);
    setShowAttachModal(true);
  }, []);

  // Handler for detach
  const handleDetach = useCallback(async (volume: SystemProviderVolume) => {
    setDetaching(true);
    try {
      await systemApi.detachVolume(volume.id);
      addNotification({
        type: 'success',
        message: 'Volume detached successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to detach volume: ${errorMessage}`
      });
    } finally {
      setDetaching(false);
    }
  }, [addNotification]);

  // Handler for snapshot
  const handleSnapshot = useCallback(async (volume: SystemProviderVolume) => {
    try {
      await systemApi.createVolumeSnapshot(volume.id, `${volume.name}-snapshot`);
      addNotification({
        type: 'success',
        message: 'Snapshot creation started'
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to create snapshot: ${errorMessage}`
      });
    }
  }, [addNotification]);

  // Handler for editing from detail modal
  const handleEditFromDetail = useCallback((volume: SystemProviderVolume) => {
    setShowDetailModal(false);
    setSelectedVolumeId(null);
    setEditVolume(volume);
    setShowFormModal(true);
  }, []);

  // Handler for volume attached
  const handleVolumeAttached = useCallback(() => {
    setRefreshKey(prev => prev + 1);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Volumes' }
  ];

  // Page actions
  const actions: PageAction[] = canCreate ? [
    {
      label: 'Create Volume',
      icon: HardDrive,
      onClick: handleCreate,
      variant: 'primary' as const
    }
  ] : [];

  return (
    <PageContainer
      title="Storage Volumes"
      description="Manage storage volumes for your infrastructure"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Volume List */}
      <VolumeList
        key={refreshKey}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={canDelete ? handleDeleteClick : undefined}
        onCreate={canCreate ? handleCreate : undefined}
        onAttach={handleAttach}
        onDetach={handleDetach}
        onSnapshot={handleSnapshot}
      />

      {/* Detail Modal */}
      <VolumeDetailModal
        volumeId={selectedVolumeId}
        isOpen={showDetailModal}
        onClose={() => {
          setShowDetailModal(false);
          setSelectedVolumeId(null);
        }}
        onVolumeUpdated={() => setRefreshKey(prev => prev + 1)}
        onEdit={handleEditFromDetail}
      />

      {/* Create/Edit Modal */}
      <VolumeFormModal
        volume={editVolume}
        isOpen={showFormModal}
        onClose={() => {
          setShowFormModal(false);
          setEditVolume(null);
        }}
        onVolumeSaved={handleVolumeSaved}
      />

      {/* Attach Modal */}
      <VolumeAttachModal
        volume={attachVolume}
        isOpen={showAttachModal}
        onClose={() => {
          setShowAttachModal(false);
          setAttachVolume(null);
        }}
        onVolumeAttached={handleVolumeAttached}
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
                  Delete Volume
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this volume? This action cannot be undone
                  and all data on the volume will be permanently lost.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowDeleteConfirm(false);
                      setVolumeToDelete(null);
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteConfirm}
                    disabled={deleting}
                  >
                    {deleting ? 'Deleting...' : 'Delete Volume'}
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

export default VolumesPage;
