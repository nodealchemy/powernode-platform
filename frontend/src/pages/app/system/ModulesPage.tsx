import React, { useState, useCallback } from 'react';
import { Package } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ModuleList, ModuleDetailModal, ModuleFormModal, ModuleCategoryFormModal } from '@/features/system/components/modules';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeModule, SystemNodeModuleCategory } from '@/features/system/types/system.types';

/**
 * ModulesPage - Main page for managing node modules
 *
 * Features:
 * - List modules with category sidebar filtering
 * - Create, view, edit, delete modules
 * - View module specifications and dependencies
 * - Permission-based access control
 */
const ModulesPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.modules.create');
  const canDelete = hasPermission('system.modules.delete');

  // Modal state
  const [showFormModal, setShowFormModal] = useState(false);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [selectedModuleId, setSelectedModuleId] = useState<string | null>(null);
  const [editModule, setEditModule] = useState<SystemNodeModule | null>(null);
  const [moduleToDelete, setModuleToDelete] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [deleting, setDeleting] = useState(false);

  // Category management state
  const [categories, setCategories] = useState<SystemNodeModuleCategory[]>([]);
  const [showCategoryFormModal, setShowCategoryFormModal] = useState(false);
  const [editCategory, setEditCategory] = useState<SystemNodeModuleCategory | null>(null);
  const [categoryToDelete, setCategoryToDelete] = useState<string | null>(null);
  const [showCategoryDeleteConfirm, setShowCategoryDeleteConfirm] = useState(false);
  const [deletingCategory, setDeletingCategory] = useState(false);

  // Fetch categories on mount
  React.useEffect(() => {
    const fetchCategories = async () => {
      try {
        const data = await systemApi.getModuleCategories();
        setCategories(data);
      } catch {
        // Categories are optional, don't show error
      }
    };
    fetchCategories();
  }, [refreshKey]);

  // Handler for viewing a module
  const handleView = useCallback((module: SystemNodeModule) => {
    setSelectedModuleId(module.id);
    setShowDetailModal(true);
  }, []);

  // Handler for editing a module
  const handleEdit = useCallback((module: SystemNodeModule) => {
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
      await systemApi.deleteModule(moduleToDelete);
      addNotification({
        type: 'success',
        message: 'Module deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete module: ${errorMessage}`
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
  const handleEditFromDetail = useCallback((module: SystemNodeModule) => {
    setShowDetailModal(false);
    setSelectedModuleId(null);
    setEditModule(module);
    setShowFormModal(true);
  }, []);

  // Category handlers
  const handleCategoryCreate = useCallback(() => {
    setEditCategory(null);
    setShowCategoryFormModal(true);
  }, []);

  const handleCategoryEdit = useCallback((category: SystemNodeModuleCategory) => {
    setEditCategory(category);
    setShowCategoryFormModal(true);
  }, []);

  const handleCategoryDeleteClick = useCallback((categoryId: string) => {
    setCategoryToDelete(categoryId);
    setShowCategoryDeleteConfirm(true);
  }, []);

  const handleCategoryDeleteConfirm = async () => {
    if (!categoryToDelete) return;

    setDeletingCategory(true);
    try {
      await systemApi.deleteModuleCategory(categoryToDelete);
      addNotification({
        type: 'success',
        message: 'Category deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete category: ${errorMessage}`
      });
    } finally {
      setDeletingCategory(false);
      setShowCategoryDeleteConfirm(false);
      setCategoryToDelete(null);
    }
  };

  const handleCategorySaved = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    setEditCategory(null);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Modules' }
  ];

  // Page actions
  const actions: PageAction[] = canCreate ? [
    {
      label: 'Create Module',
      icon: Package,
      onClick: handleCreate,
      variant: 'primary' as const
    }
  ] : [];

  return (
    <PageContainer
      title="Node Modules"
      description="Manage reusable configuration modules for node deployment"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Module List */}
      <ModuleList
        key={refreshKey}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={canDelete ? handleDeleteClick : undefined}
        onCreate={canCreate ? handleCreate : undefined}
        onCategoryCreate={canCreate ? handleCategoryCreate : undefined}
        onCategoryEdit={handleCategoryEdit}
        onCategoryDelete={handleCategoryDeleteClick}
      />

      {/* Detail Modal */}
      <ModuleDetailModal
        moduleId={selectedModuleId}
        isOpen={showDetailModal}
        onClose={() => {
          setShowDetailModal(false);
          setSelectedModuleId(null);
        }}
        onEdit={handleEditFromDetail}
      />

      {/* Create/Edit Modal */}
      <ModuleFormModal
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
                  Delete Module
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this module? This action cannot be undone.
                  Nodes using this module will need to be reconfigured.
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

      {/* Category Create/Edit Modal */}
      <ModuleCategoryFormModal
        category={editCategory}
        categories={categories}
        isOpen={showCategoryFormModal}
        onClose={() => {
          setShowCategoryFormModal(false);
          setEditCategory(null);
        }}
        onCategorySaved={handleCategorySaved}
      />

      {/* Category Delete Confirmation Modal */}
      {showCategoryDeleteConfirm && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div
            className="fixed inset-0 bg-black/50 transition-opacity"
            onClick={() => setShowCategoryDeleteConfirm(false)}
          />
          <div className="flex min-h-full items-center justify-center p-4">
            <div className="relative w-full max-w-md bg-theme-surface rounded-lg shadow-xl">
              <div className="p-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-2">
                  Delete Category
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this category? This action cannot be undone.
                  Modules in this category will need to be reassigned.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowCategoryDeleteConfirm(false);
                      setCategoryToDelete(null);
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleCategoryDeleteConfirm}
                    disabled={deletingCategory}
                  >
                    {deletingCategory ? 'Deleting...' : 'Delete Category'}
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

export default ModulesPage;
