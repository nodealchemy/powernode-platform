import React, { useState, useCallback } from 'react';
import { Server } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { NodeList, NodeDetailModal, CreateNodeModal, EditNodeModal } from '@/features/system/components/nodes';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNode } from '@/features/system/types/system.types';

/**
 * NodesPage - Infrastructure Nodes Management Page
 *
 * Displays a list of nodes with full CRUD capabilities:
 * - Create new nodes via modal
 * - View node details in multi-tab modal
 * - Edit nodes (to be implemented)
 * - Delete nodes with confirmation
 * - Toggle node enabled/disabled status
 */
const NodesPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.nodes.create');
  const canUpdate = hasPermission('system.nodes.update');
  const canDelete = hasPermission('system.nodes.delete');

  // Modal state
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editNode, setEditNode] = useState<SystemNode | null>(null);
  const [deleteConfirmNode, setDeleteConfirmNode] = useState<SystemNode | null>(null);
  const [deleting, setDeleting] = useState(false);

  // Refresh key to trigger NodeList refresh
  const [refreshKey, setRefreshKey] = useState(0);

  // Helper to trigger list refresh
  const triggerRefresh = useCallback(() => {
    setRefreshKey(prev => prev + 1);
  }, []);

  // Handler: View node details
  const handleViewNode = useCallback((node: SystemNode) => {
    setSelectedNodeId(node.id);
    setShowDetailModal(true);
  }, []);

  // Handler: Edit node
  const handleEditNode = useCallback((node: SystemNode) => {
    setEditNode(node);
  }, []);

  // Handler: Node edit completed
  const handleNodeEditComplete = useCallback(() => {
    setEditNode(null);
    triggerRefresh();
  }, [triggerRefresh]);

  // Handler: Delete node (show confirmation)
  const handleDeleteNode = useCallback((nodeId: string) => {
    // Fetch node details for confirmation display
    systemApi.getNode(nodeId).then(node => {
      setDeleteConfirmNode(node);
    }).catch(() => {
      addNotification({
        type: 'error',
        message: 'Failed to load node details for deletion'
      });
    });
  }, [addNotification]);

  // Handler: Confirm delete
  const handleConfirmDelete = useCallback(async () => {
    if (!deleteConfirmNode) return;

    setDeleting(true);
    try {
      await systemApi.deleteNode(deleteConfirmNode.id);
      addNotification({
        type: 'success',
        message: `Node "${deleteConfirmNode.name}" deleted successfully`
      });
      setDeleteConfirmNode(null);
      triggerRefresh();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to delete node';
      addNotification({
        type: 'error',
        message: errorMessage
      });
    } finally {
      setDeleting(false);
    }
  }, [deleteConfirmNode, addNotification, triggerRefresh]);

  // Handler: Toggle enabled
  const handleToggleEnabled = useCallback(async (node: SystemNode) => {
    try {
      await systemApi.updateNode(node.id, { enabled: !node.enabled });
      addNotification({
        type: 'success',
        message: `Node "${node.name}" ${node.enabled ? 'disabled' : 'enabled'} successfully`
      });
      triggerRefresh();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to update node';
      addNotification({
        type: 'error',
        message: errorMessage
      });
    }
  }, [addNotification, triggerRefresh]);

  // Handler: Create node modal
  const handleCreateClick = useCallback(() => {
    setShowCreateModal(true);
  }, []);

  // Handler: Node created
  const handleNodeCreated = useCallback(() => {
    triggerRefresh();
  }, [triggerRefresh]);

  // Handler: Node updated (from detail modal)
  const handleNodeUpdated = useCallback(() => {
    triggerRefresh();
  }, [triggerRefresh]);

  // Build page actions
  const pageActions = [];
  if (canCreate) {
    pageActions.push({
      label: 'Create Node',
      onClick: handleCreateClick,
      variant: 'primary' as const,
      icon: Server
    });
  }

  return (
    <PageContainer
      title="Infrastructure Nodes"
      description="Manage your infrastructure nodes and instances"
      breadcrumbs={[
        { label: 'System', href: '/app/system' },
        { label: 'Nodes' }
      ]}
      actions={pageActions}
    >
      <NodeList
        onView={handleViewNode}
        onEdit={canUpdate ? handleEditNode : undefined}
        onDelete={canDelete ? handleDeleteNode : undefined}
        onCreate={canCreate ? handleCreateClick : undefined}
        onToggleEnabled={canUpdate ? handleToggleEnabled : undefined}
        refreshKey={refreshKey}
      />

      {/* Node Detail Modal */}
      <NodeDetailModal
        nodeId={selectedNodeId}
        isOpen={showDetailModal}
        onClose={() => {
          setShowDetailModal(false);
          setSelectedNodeId(null);
        }}
        onNodeUpdated={handleNodeUpdated}
      />

      {/* Create Node Modal */}
      <CreateNodeModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onNodeCreated={handleNodeCreated}
      />

      {/* Edit Node Modal */}
      <EditNodeModal
        node={editNode}
        isOpen={!!editNode}
        onClose={() => setEditNode(null)}
        onNodeUpdated={handleNodeEditComplete}
      />

      {/* Delete Confirmation Modal */}
      <Modal
        isOpen={!!deleteConfirmNode}
        onClose={() => setDeleteConfirmNode(null)}
        title="Delete Node"
        subtitle="This action cannot be undone"
        size="md"
        footer={
          <div className="flex items-center justify-end gap-3">
            <Button variant="ghost" onClick={() => setDeleteConfirmNode(null)} disabled={deleting}>
              Cancel
            </Button>
            <Button variant="danger" onClick={handleConfirmDelete} disabled={deleting}>
              {deleting ? 'Deleting...' : 'Delete Node'}
            </Button>
          </div>
        }
      >
        <div className="space-y-4">
          <p className="text-theme-primary">
            Are you sure you want to delete the node <strong>{deleteConfirmNode?.name}</strong>?
          </p>
          {deleteConfirmNode && (deleteConfirmNode.instance_count || 0) > 0 && (
            <div className="p-3 bg-theme-warning/10 border border-theme-warning/30 rounded-lg">
              <p className="text-theme-warning text-sm">
                <strong>Warning:</strong> This node has {deleteConfirmNode.instance_count} instance(s).
                Deleting this node will also remove all associated instances.
              </p>
            </div>
          )}
        </div>
      </Modal>
    </PageContainer>
  );
};

export default NodesPage;
