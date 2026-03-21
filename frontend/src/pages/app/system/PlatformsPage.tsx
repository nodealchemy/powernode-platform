import React, { useState, useCallback } from 'react';
import { Layers } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { PlatformList, PlatformFormModal } from '@/features/system/components/platforms';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodePlatform } from '@/features/system/types/system.types';

/**
 * PlatformsPage - Main page for managing node platforms
 *
 * Features:
 * - List platforms with search and filters
 * - Create, edit, delete platforms
 * - View platform scripts
 * - Permission-based access control
 */
const PlatformsPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.platforms.create');
  const canDelete = hasPermission('system.platforms.delete');

  // Modal state
  const [showFormModal, setShowFormModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [editPlatform, setEditPlatform] = useState<SystemNodePlatform | null>(null);
  const [platformToDelete, setPlatformToDelete] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [deleting, setDeleting] = useState(false);

  // Handler for viewing a platform (opens edit modal in view mode)
  const handleView = useCallback((platform: SystemNodePlatform) => {
    setEditPlatform(platform);
    setShowFormModal(true);
  }, []);

  // Handler for editing a platform
  const handleEdit = useCallback((platform: SystemNodePlatform) => {
    setEditPlatform(platform);
    setShowFormModal(true);
  }, []);

  // Handler for initiating delete
  const handleDeleteClick = useCallback((platformId: string) => {
    setPlatformToDelete(platformId);
    setShowDeleteConfirm(true);
  }, []);

  // Handler for confirming delete
  const handleDeleteConfirm = async () => {
    if (!platformToDelete) return;

    setDeleting(true);
    try {
      await systemApi.deletePlatform(platformToDelete);
      addNotification({
        type: 'success',
        message: 'Platform deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete platform: ${errorMessage}`
      });
    } finally {
      setDeleting(false);
      setShowDeleteConfirm(false);
      setPlatformToDelete(null);
    }
  };

  // Handler for platform created/updated
  const handlePlatformSaved = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    setEditPlatform(null);
  }, []);

  // Handler for opening create modal
  const handleCreate = useCallback(() => {
    setEditPlatform(null);
    setShowFormModal(true);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Platforms' }
  ];

  // Page actions
  const actions: PageAction[] = canCreate ? [
    {
      label: 'Create Platform',
      icon: Layers,
      onClick: handleCreate,
      variant: 'primary' as const
    }
  ] : [];

  return (
    <PageContainer
      title="Node Platforms"
      description="Manage node platforms defining OS and initialization scripts"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Platform List */}
      <PlatformList
        key={refreshKey}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={canDelete ? handleDeleteClick : undefined}
        onCreate={canCreate ? handleCreate : undefined}
      />

      {/* Create/Edit Modal */}
      <PlatformFormModal
        isOpen={showFormModal}
        onClose={() => {
          setShowFormModal(false);
          setEditPlatform(null);
        }}
        onPlatformSaved={handlePlatformSaved}
        editPlatform={editPlatform}
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
                  Delete Platform
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this platform? This action cannot be undone.
                  Templates using this platform will need to be updated.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowDeleteConfirm(false);
                      setPlatformToDelete(null);
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteConfirm}
                    disabled={deleting}
                  >
                    {deleting ? 'Deleting...' : 'Delete Platform'}
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

export default PlatformsPage;
