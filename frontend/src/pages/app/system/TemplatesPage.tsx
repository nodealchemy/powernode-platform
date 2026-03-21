import React, { useState, useCallback } from 'react';
import { FileText } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { TemplateList, TemplateDetailModal, CreateTemplateModal } from '@/features/system/components/templates';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeTemplate } from '@/features/system/types/system.types';

/**
 * TemplatesPage - Main page for managing node templates
 *
 * Features:
 * - List templates with search and filters
 * - Create, view, edit, delete templates
 * - Duplicate templates
 * - Permission-based access control
 */
const TemplatesPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.templates.create');
  const canDelete = hasPermission('system.templates.delete');

  // Modal state
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [selectedTemplateId, setSelectedTemplateId] = useState<string | null>(null);
  const [editTemplate, setEditTemplate] = useState<SystemNodeTemplate | null>(null);
  const [duplicateTemplate, setDuplicateTemplate] = useState<SystemNodeTemplate | null>(null);
  const [templateToDelete, setTemplateToDelete] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [deleting, setDeleting] = useState(false);

  // Handler for viewing a template
  const handleView = useCallback((template: SystemNodeTemplate) => {
    setSelectedTemplateId(template.id);
    setShowDetailModal(true);
  }, []);

  // Handler for editing a template
  const handleEdit = useCallback((template: SystemNodeTemplate) => {
    setEditTemplate(template);
    setDuplicateTemplate(null);
    setShowCreateModal(true);
  }, []);

  // Handler for editing from detail modal
  const handleEditFromDetail = useCallback((template: SystemNodeTemplate) => {
    setShowDetailModal(false);
    setSelectedTemplateId(null);
    setEditTemplate(template);
    setDuplicateTemplate(null);
    setShowCreateModal(true);
  }, []);

  // Handler for duplicating a template
  const handleDuplicate = useCallback((template: SystemNodeTemplate) => {
    setDuplicateTemplate(template);
    setEditTemplate(null);
    setShowCreateModal(true);
  }, []);

  // Handler for initiating delete
  const handleDeleteClick = useCallback((templateId: string) => {
    setTemplateToDelete(templateId);
    setShowDeleteConfirm(true);
  }, []);

  // Handler for confirming delete
  const handleDeleteConfirm = async () => {
    if (!templateToDelete) return;

    setDeleting(true);
    try {
      await systemApi.deleteTemplate(templateToDelete);
      addNotification({
        type: 'success',
        message: 'Template deleted successfully'
      });
      setRefreshKey(prev => prev + 1);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete template: ${errorMessage}`
      });
    } finally {
      setDeleting(false);
      setShowDeleteConfirm(false);
      setTemplateToDelete(null);
    }
  };

  // Handler for template created/updated
  const handleTemplateCreated = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    setEditTemplate(null);
    setDuplicateTemplate(null);
  }, []);

  // Handler for opening create modal
  const handleCreate = useCallback(() => {
    setEditTemplate(null);
    setDuplicateTemplate(null);
    setShowCreateModal(true);
  }, []);

  // Breadcrumbs
  const breadcrumbs = [
    { label: 'System', href: '/app/system' },
    { label: 'Templates' }
  ];

  // Page actions
  const actions: PageAction[] = canCreate ? [
    {
      label: 'Create Template',
      icon: FileText,
      onClick: handleCreate,
      variant: 'primary' as const
    }
  ] : [];

  return (
    <PageContainer
      title="Node Templates"
      description="Manage node configuration templates to standardize your infrastructure"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Template List */}
      <TemplateList
        key={refreshKey}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={canDelete ? handleDeleteClick : undefined}
        onCreate={canCreate ? handleCreate : undefined}
        onDuplicate={canCreate ? handleDuplicate : undefined}
      />

      {/* Detail Modal */}
      <TemplateDetailModal
        templateId={selectedTemplateId}
        isOpen={showDetailModal}
        onClose={() => {
          setShowDetailModal(false);
          setSelectedTemplateId(null);
        }}
        onTemplateUpdated={() => setRefreshKey(prev => prev + 1)}
        onEdit={handleEditFromDetail}
      />

      {/* Create/Edit Modal */}
      <CreateTemplateModal
        isOpen={showCreateModal}
        onClose={() => {
          setShowCreateModal(false);
          setEditTemplate(null);
          setDuplicateTemplate(null);
        }}
        onTemplateCreated={handleTemplateCreated}
        editTemplate={editTemplate}
        duplicateFrom={duplicateTemplate}
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
                  Delete Template
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete this template? This action cannot be undone.
                  Any nodes using this template will retain their current configuration.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => {
                      setShowDeleteConfirm(false);
                      setTemplateToDelete(null);
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteConfirm}
                    disabled={deleting}
                  >
                    {deleting ? 'Deleting...' : 'Delete Template'}
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

export default TemplatesPage;
