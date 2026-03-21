import React, { useState, useCallback } from 'react';
import { Package } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { PuppetModuleList, PuppetModuleDetailModal, PuppetModuleFormModal } from '@/features/system/components/puppet';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemPuppetModule } from '@/features/system/types/system.types';

/**
 * PuppetModulesPage - Main page for managing Puppet modules
 *
 * Features:
 * - List Puppet modules with filtering
 * - Create, view, edit, delete modules
 * - View module resources and dependencies
 * - Permission-based access control
 */
const PuppetModulesPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.puppet.create');
  const canDelete = hasPermission('system.puppet.delete');

  // Modal state
  const [showFormModal, setShowFormModal] = useState(false);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [selectedModuleId, setSelectedModuleId] = useState<string | null>(null);
  const [editModule, setEditModule] = useState<SystemPuppetModule | null>(null);
  const [moduleToDelete, setModuleToDelete] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [deleting, setDeleting] = useState(false);

  // Handler for viewing a module
  const handleView = useCallback((module: SystemPuppetModule) => {
    setSelectedModuleId(module.id);
    setShowDetailModal(true);
  }, []);

  // Handler for editing a module
  const handleEdit = useCallback((module: SystemPuppetModule) => {
    setEditModule(module);
    setShowFormModal(true);
  }, []);

  // Handler for initiating delete
  const handleDeleteClick = useCallback((moduleId: string) => {
    setModuleToDelete(moduleId);
    setShowDeleteConfirm(true);
  }, []);

  // Handler for confirming delete
  const handleDeleteConfirm = async () => {
    if (!moduleToDelete) return;

    setDeleting(true);
    try {
      await systemApi.deletePuppetModule(moduleToDelete);
      addNotification({
        type: 'success',
        message: 'Puppet module deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete Puppet module: ${errorMessage}`
      });
    } finally {
      setDeleting(false);
      setShowDeleteConfirm(false);
      setModuleToDelete(null);
    }
  };

  // Handler for module created/updated
  const handleModuleSaved = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    setEditModule(null);
  }, []);

  // Handler for opening create modal
  const handleCreate = useCallback(() => {
    setEditModule(null);
    setShowFormModal(true);
  }, []);

  // Handler for editing from detail modal
  const handleEditFromDetail = useCallback((module: SystemPuppetModule) => {
    setShowDetailModal(false);
    setSelectedModuleId(null);
    setEditModule(module);
    setShowFormModal(true);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Puppet Modules' }
  ];

  // Page actions
  const actions: PageAction[] = canCreate ? [
    {
      label: 'Add Puppet Module',
      icon: Package,
      onClick: handleCreate,
      variant: 'primary' as const
    }
  ] : [];

  return (
    <PageContainer
      title="Puppet Modules"
      description="Manage Puppet configuration management modules"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Puppet Module List */}
      <PuppetModuleList
        key={refreshKey}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={canDelete ? handleDeleteClick : undefined}
        onCreate={canCreate ? handleCreate : undefined}
      />

      {/* Detail Modal */}
      <PuppetModuleDetailModal
        moduleId={selectedModuleId}
        isOpen={showDetailModal}
        onClose={() => {
          setShowDetailModal(false);
          setSelectedModuleId(null);
        }}
        onEdit={handleEditFromDetail}
      />

      {/* Create/Edit Modal */}
      <PuppetModuleFormModal
        isOpen={showFormModal}
        onClose={() => {
          setShowFormModal(false);
          setEditModule(null);
        }}
        onModuleSaved={handleModuleSaved}
        editModule={editModule}
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
                  Delete Puppet Module
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this Puppet module? This action cannot be undone.
                  All resources and node module assignments will also be removed.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowDeleteConfirm(false);
                      setModuleToDelete(null);
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteConfirm}
                    disabled={deleting}
                  >
                    {deleting ? 'Deleting...' : 'Delete Module'}
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

export default PuppetModulesPage;
