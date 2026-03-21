import React, { useState, useCallback } from 'react';
import { Cpu } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ArchitectureList, ArchitectureFormModal } from '@/features/system/components/architectures';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeArchitecture } from '@/features/system/types/system.types';

/**
 * ArchitecturesPage - Main page for managing node architectures
 *
 * Features:
 * - List architectures with search and filters
 * - Create, edit, delete architectures
 * - View architecture kernel options
 * - Permission-based access control
 */
const ArchitecturesPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.architectures.create');
  const canDelete = hasPermission('system.architectures.delete');

  // Modal state
  const [showFormModal, setShowFormModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [editArchitecture, setEditArchitecture] = useState<SystemNodeArchitecture | null>(null);
  const [architectureToDelete, setArchitectureToDelete] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [deleting, setDeleting] = useState(false);

  // Handler for viewing an architecture (opens edit modal in view mode)
  const handleView = useCallback((architecture: SystemNodeArchitecture) => {
    setEditArchitecture(architecture);
    setShowFormModal(true);
  }, []);

  // Handler for editing an architecture
  const handleEdit = useCallback((architecture: SystemNodeArchitecture) => {
    setEditArchitecture(architecture);
    setShowFormModal(true);
  }, []);

  // Handler for initiating delete
  const handleDeleteClick = useCallback((architectureId: string) => {
    setArchitectureToDelete(architectureId);
    setShowDeleteConfirm(true);
  }, []);

  // Handler for confirming delete
  const handleDeleteConfirm = async () => {
    if (!architectureToDelete) return;

    setDeleting(true);
    try {
      await systemApi.deleteArchitecture(architectureToDelete);
      addNotification({
        type: 'success',
        message: 'Architecture deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete architecture: ${errorMessage}`
      });
    } finally {
      setDeleting(false);
      setShowDeleteConfirm(false);
      setArchitectureToDelete(null);
    }
  };

  // Handler for architecture created/updated
  const handleArchitectureSaved = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    setEditArchitecture(null);
  }, []);

  // Handler for opening create modal
  const handleCreate = useCallback(() => {
    setEditArchitecture(null);
    setShowFormModal(true);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Architectures' }
  ];

  // Page actions
  const actions: PageAction[] = canCreate ? [
    {
      label: 'Create Architecture',
      icon: Cpu,
      onClick: handleCreate,
      variant: 'primary' as const
    }
  ] : [];

  return (
    <PageContainer
      title="Node Architectures"
      description="Manage node architectures defining hardware and kernel configurations"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Architecture List */}
      <ArchitectureList
        key={refreshKey}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={canDelete ? handleDeleteClick : undefined}
        onCreate={canCreate ? handleCreate : undefined}
      />

      {/* Create/Edit Modal */}
      <ArchitectureFormModal
        isOpen={showFormModal}
        onClose={() => {
          setShowFormModal(false);
          setEditArchitecture(null);
        }}
        onArchitectureSaved={handleArchitectureSaved}
        editArchitecture={editArchitecture}
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
                  Delete Architecture
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this architecture? This action cannot be undone.
                  Platforms using this architecture will need to be updated.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowDeleteConfirm(false);
                      setArchitectureToDelete(null);
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteConfirm}
                    disabled={deleting}
                  >
                    {deleting ? 'Deleting...' : 'Delete Architecture'}
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

export default ArchitecturesPage;
