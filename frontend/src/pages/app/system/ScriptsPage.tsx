import React, { useState, useCallback } from 'react';
import { FileCode } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ScriptList, ScriptFormModal } from '@/features/system/components/scripts';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeScript } from '@/features/system/types/system.types';

/**
 * ScriptsPage - Main page for managing node scripts
 *
 * Features:
 * - List scripts with search and filters
 * - Create, view, edit, delete scripts
 * - View script content
 * - Permission-based access control
 */
const ScriptsPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.scripts.create');
  const canDelete = hasPermission('system.scripts.delete');

  // Modal state
  const [showFormModal, setShowFormModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [editScript, setEditScript] = useState<SystemNodeScript | null>(null);
  const [scriptToDelete, setScriptToDelete] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [deleting, setDeleting] = useState(false);

  // Handler for viewing a script (opens edit modal)
  const handleView = useCallback((script: SystemNodeScript) => {
    setEditScript(script);
    setShowFormModal(true);
  }, []);

  // Handler for editing a script
  const handleEdit = useCallback((script: SystemNodeScript) => {
    setEditScript(script);
    setShowFormModal(true);
  }, []);

  // Handler for initiating delete
  const handleDeleteClick = useCallback((scriptId: string) => {
    setScriptToDelete(scriptId);
    setShowDeleteConfirm(true);
  }, []);

  // Handler for confirming delete
  const handleDeleteConfirm = async () => {
    if (!scriptToDelete) return;

    setDeleting(true);
    try {
      await systemApi.deleteScript(scriptToDelete);
      addNotification({
        type: 'success',
        message: 'Script deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete script: ${errorMessage}`
      });
    } finally {
      setDeleting(false);
      setShowDeleteConfirm(false);
      setScriptToDelete(null);
    }
  };

  // Handler for script created/updated
  const handleScriptSaved = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    setEditScript(null);
  }, []);

  // Handler for opening create modal
  const handleCreate = useCallback(() => {
    setEditScript(null);
    setShowFormModal(true);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Scripts' }
  ];

  // Page actions
  const actions: PageAction[] = canCreate ? [
    {
      label: 'Create Script',
      icon: FileCode,
      onClick: handleCreate,
      variant: 'primary' as const
    }
  ] : [];

  return (
    <PageContainer
      title="Node Scripts"
      description="Manage reusable scripts for node configuration and automation"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Script List */}
      <ScriptList
        key={refreshKey}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={canDelete ? handleDeleteClick : undefined}
        onCreate={canCreate ? handleCreate : undefined}
      />

      {/* Create/Edit Modal */}
      <ScriptFormModal
        isOpen={showFormModal}
        onClose={() => {
          setShowFormModal(false);
          setEditScript(null);
        }}
        onScriptSaved={handleScriptSaved}
        editScript={editScript}
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
                  Delete Script
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this script? This action cannot be undone.
                  Platforms using this script will need to be updated.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowDeleteConfirm(false);
                      setScriptToDelete(null);
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteConfirm}
                    disabled={deleting}
                  >
                    {deleting ? 'Deleting...' : 'Delete Script'}
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

export default ScriptsPage;
