import React, { useState, useEffect, useCallback } from 'react';
import { Server, Cpu, Box, Activity, Copy, Check, Globe, Shield, Clock, Settings, Plus, Edit, Trash2 } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { TabContainer, Tab } from '@/shared/components/ui/TabContainer';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import {
  useSystemWebSocket,
  type OperationProgressPayload,
  type OperationUpdatePayload,
  type InstanceUpdatePayload,
  type NodeUpdatePayload
} from '@/features/system/hooks/useSystemWebSocket';
import type { SystemNode, SystemNodeInstance, SystemNodeModule, SystemOperation } from '@/features/system/types/system.types';
import NodeInstanceControls from './NodeInstanceControls';
import { EditNodeModal } from './EditNodeModal';
import { CreateInstanceModal } from './CreateInstanceModal';
import { EditInstanceModal } from './EditInstanceModal';

interface NodeDetailModalProps {
  /** Node ID to display */
  nodeId: string | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when node is updated (e.g., after an action) */
  onNodeUpdated?: () => void;
}

/**
 * NodeDetailModal - Multi-tab modal for viewing node details
 *
 * Displays node information, instances, modules, and operations
 * with real-time WebSocket updates for operation progress.
 */
export const NodeDetailModal: React.FC<NodeDetailModalProps> = ({
  nodeId,
  isOpen,
  onClose,
  onNodeUpdated
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // State
  const [node, setNode] = useState<SystemNode | null>(null);
  const [instances, setInstances] = useState<SystemNodeInstance[]>([]);
  const [modules, setModules] = useState<SystemNodeModule[]>([]);
  const [operations, setOperations] = useState<SystemOperation[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('info');
  const [copiedField, setCopiedField] = useState<string | null>(null);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showCreateInstanceModal, setShowCreateInstanceModal] = useState(false);
  const [editInstance, setEditInstance] = useState<SystemNodeInstance | null>(null);

  // Permissions
  const canViewInstances = hasPermission('system.instances.read');
  const canViewModules = hasPermission('system.modules.read');
  const canViewOperations = hasPermission('system.infra_operations.read');
  const canControlInstances = hasPermission('system.instances.control');
  const canCreateInstances = hasPermission('system.instances.create');
  const canUpdateInstances = hasPermission('system.instances.update');
  const canDeleteInstances = hasPermission('system.instances.delete');
  const canUpdateNode = hasPermission('system.nodes.update');

  // Delete instance state
  const [deleteInstanceConfirm, setDeleteInstanceConfirm] = useState<SystemNodeInstance | null>(null);
  const [deletingInstance, setDeletingInstance] = useState(false);

  // WebSocket for real-time updates
  useSystemWebSocket({
    onOperationProgress: useCallback((progress: OperationProgressPayload) => {
      setOperations(prev => prev.map(op =>
        op.id === progress.operation_id
          ? { ...op, status: progress.status, progress: progress.progress, description: progress.description }
          : op
      ));
    }, []),
    onOperationUpdate: useCallback((operation: OperationUpdatePayload) => {
      setOperations(prev => {
        const exists = prev.some(op => op.id === operation.id);
        if (exists) {
          return prev.map(op => op.id === operation.id ? { ...op, ...operation } as SystemOperation : op);
        }
        // New operation for this node - add if it belongs to this node
        if (operation.operable_type === 'System::Node' && operation.operable_id === nodeId) {
          return [operation as unknown as SystemOperation, ...prev];
        }
        return prev;
      });
    }, [nodeId]),
    onInstanceUpdate: useCallback((instance: InstanceUpdatePayload) => {
      if (instance.node_id === nodeId) {
        setInstances(prev => prev.map(i => i.id === instance.id ? { ...i, ...instance } as SystemNodeInstance : i));
      }
    }, [nodeId]),
    onNodeUpdate: useCallback((updatedNode: NodeUpdatePayload) => {
      if (updatedNode.id === nodeId) {
        setNode(prev => prev ? { ...prev, ...updatedNode } as SystemNode : null);
      }
    }, [nodeId])
  });

  // Fetch node data
  const fetchNodeData = useCallback(async () => {
    if (!nodeId) return;

    setLoading(true);
    try {
      // Fetch node details
      const nodeData = await systemApi.getNode(nodeId);
      setNode(nodeData);

      // Fetch related data in parallel
      const fetchPromises: Promise<void>[] = [];

      if (canViewInstances) {
        fetchPromises.push(
          systemApi.getNodeInstances(nodeId).then(data => setInstances(data.node_instances || []))
        );
      }

      if (canViewModules) {
        fetchPromises.push(
          systemApi.getNodeModules({ node_id: nodeId }).then(data => setModules(data.node_modules || []))
        );
      }

      if (canViewOperations) {
        fetchPromises.push(
          systemApi.getOperations({ per_page: 50 })
            .then(data => {
              // Filter operations that belong to this node
              const nodeOps = data.operations.filter(op =>
                op.operable_type === 'System::Node' && op.operable_id === nodeId
              );
              setOperations(nodeOps || []);
            })
        );
      }

      await Promise.all(fetchPromises);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load node details'
      });
    } finally {
      setLoading(false);
    }
  }, [nodeId, canViewInstances, canViewModules, canViewOperations, addNotification]);

  // Load data when modal opens
  useEffect(() => {
    if (isOpen && nodeId) {
      fetchNodeData();
      setActiveTab('info');
    }
  }, [isOpen, nodeId, fetchNodeData]);

  // Copy to clipboard helper
  const copyToClipboard = useCallback(async (text: string, field: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopiedField(field);
      setTimeout(() => setCopiedField(null), 2000);
    } catch {
      addNotification({ type: 'error', message: 'Failed to copy to clipboard' });
    }
  }, [addNotification]);

  // Handle instance action completion
  const handleInstanceActionComplete = useCallback(() => {
    fetchNodeData();
    onNodeUpdated?.();
  }, [fetchNodeData, onNodeUpdated]);

  // Handle node edit completion
  const handleNodeEditComplete = useCallback((updatedNode: SystemNode) => {
    setNode(updatedNode);
    setShowEditModal(false);
    onNodeUpdated?.();
  }, [onNodeUpdated]);

  // Handle instance created
  const handleInstanceCreated = useCallback((newInstance: SystemNodeInstance) => {
    setInstances(prev => [...prev, newInstance]);
    setShowCreateInstanceModal(false);
    onNodeUpdated?.();
  }, [onNodeUpdated]);

  // Handle instance edit completion
  const handleInstanceEditComplete = useCallback((updatedInstance: SystemNodeInstance) => {
    setInstances(prev => prev.map(i => i.id === updatedInstance.id ? updatedInstance : i));
    setEditInstance(null);
    onNodeUpdated?.();
  }, [onNodeUpdated]);

  // Handle instance delete
  const handleDeleteInstance = useCallback(async () => {
    if (!deleteInstanceConfirm || !nodeId) return;

    setDeletingInstance(true);
    try {
      await systemApi.deleteNodeInstance(nodeId, deleteInstanceConfirm.id);
      setInstances(prev => prev.filter(i => i.id !== deleteInstanceConfirm.id));
      addNotification({
        type: 'success',
        message: `Instance "${deleteInstanceConfirm.name}" deleted successfully`
      });
      setDeleteInstanceConfirm(null);
      onNodeUpdated?.();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to delete instance';
      addNotification({ type: 'error', message: errorMessage });
    } finally {
      setDeletingInstance(false);
    }
  }, [deleteInstanceConfirm, nodeId, addNotification, onNodeUpdated]);

  // Copy IP to clipboard for instances
  const copyInstanceIp = useCallback(async (ip: string, type: string, instanceId: string) => {
    try {
      await navigator.clipboard.writeText(ip);
      setCopiedField(`${instanceId}-${type}`);
      setTimeout(() => setCopiedField(null), 2000);
    } catch {
      addNotification({ type: 'error', message: 'Failed to copy to clipboard' });
    }
  }, [addNotification]);

  // Status badge variant
  const getStatusBadge = (status?: string, enabled?: boolean) => {
    if (enabled === false) {
      return <Badge variant="secondary">Disabled</Badge>;
    }
    switch (status) {
      case 'running':
        return <Badge variant="success" dot pulse>Running</Badge>;
      case 'stopped':
        return <Badge variant="secondary">Stopped</Badge>;
      case 'pending':
        return <Badge variant="warning" dot pulse>Pending</Badge>;
      case 'error':
      case 'failed':
        return <Badge variant="danger">Failed</Badge>;
      default:
        return enabled ? <Badge variant="success">Enabled</Badge> : <Badge variant="secondary">Unknown</Badge>;
    }
  };

  // Operation status badge
  const getOperationStatusBadge = (status: SystemOperation['status']) => {
    switch (status) {
      case 'pending':
        return <Badge variant="warning">Pending</Badge>;
      case 'scheduled':
        return <Badge variant="info">Scheduled</Badge>;
      case 'running':
        return <Badge variant="primary" dot pulse>Running</Badge>;
      case 'complete':
        return <Badge variant="success">Complete</Badge>;
      case 'failed':
        return <Badge variant="danger">Failed</Badge>;
      case 'aborted':
      case 'cancelled':
        return <Badge variant="secondary">{status.charAt(0).toUpperCase() + status.slice(1)}</Badge>;
      default:
        return <Badge variant="default">{status}</Badge>;
    }
  };

  // Tab content components
  const InfoTab = () => (
    <div className="space-y-6">
      {/* Basic Info */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="space-y-4">
          <div>
            <label className="text-sm text-theme-secondary">Name</label>
            <p className="text-theme-primary font-medium">{node?.name}</p>
          </div>
          <div>
            <label className="text-sm text-theme-secondary">Description</label>
            <p className="text-theme-primary">{node?.description || '-'}</p>
          </div>
          <div>
            <label className="text-sm text-theme-secondary">Status</label>
            <div className="mt-1">{getStatusBadge(node?.status, node?.enabled)}</div>
          </div>
          <div>
            <label className="text-sm text-theme-secondary">Template</label>
            <p className="text-theme-primary">{node?.node_template_name || '-'}</p>
          </div>
        </div>

        <div className="space-y-4">
          {node?.public_address && (
            <div>
              <label className="text-sm text-theme-secondary flex items-center gap-2">
                <Globe className="w-4 h-4" />
                Public Address
              </label>
              <div className="flex items-center gap-2 mt-1">
                <code className="text-theme-primary bg-theme-surface-hover px-2 py-1 rounded font-mono text-sm">
                  {node.public_address}
                </code>
                <button
                  onClick={() => copyToClipboard(node.public_address!, 'address')}
                  className="p-1 text-theme-secondary hover:text-theme-primary rounded"
                  title="Copy address"
                >
                  {copiedField === 'address' ? <Check className="w-4 h-4 text-theme-success" /> : <Copy className="w-4 h-4" />}
                </button>
              </div>
            </div>
          )}
          <div>
            <label className="text-sm text-theme-secondary flex items-center gap-2">
              <Shield className="w-4 h-4" />
              Allocate Public IP
            </label>
            <p className="text-theme-primary">{node?.allocate_public_ip ? 'Yes' : 'No'}</p>
          </div>
          <div>
            <label className="text-sm text-theme-secondary flex items-center gap-2">
              <Cpu className="w-4 h-4" />
              Instances
            </label>
            <p className="text-theme-primary">{node?.instance_count ?? instances.length}</p>
          </div>
          <div>
            <label className="text-sm text-theme-secondary flex items-center gap-2">
              <Clock className="w-4 h-4" />
              Created
            </label>
            <p className="text-theme-primary">
              {node?.created_at ? new Date(node.created_at).toLocaleString() : '-'}
            </p>
          </div>
        </div>
      </div>

      {/* Configuration */}
      {node?.config && Object.keys(node.config).length > 0 && (
        <div>
          <label className="text-sm text-theme-secondary flex items-center gap-2 mb-2">
            <Settings className="w-4 h-4" />
            Configuration
          </label>
          <pre className="bg-theme-surface-hover rounded-lg p-4 text-sm text-theme-primary overflow-x-auto">
            {JSON.stringify(node.config, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );

  const InstancesTab = () => (
    <div className="space-y-4">
      {/* Header with Add button */}
      {canCreateInstances && (
        <div className="flex justify-end">
          <Button
            variant="primary"
            size="sm"
            onClick={() => setShowCreateInstanceModal(true)}
          >
            <Plus className="w-4 h-4 mr-1" />
            Add Instance
          </Button>
        </div>
      )}

      {instances.length === 0 ? (
        <div className="text-center py-8 text-theme-secondary">
          <Cpu className="w-12 h-12 mx-auto mb-3 opacity-50" />
          <p>No instances found</p>
          {canCreateInstances && (
            <p className="text-sm mt-2">Click "Add Instance" to create one</p>
          )}
        </div>
      ) : (
        <div className="space-y-3">
          {instances.map(instance => (
            <div
              key={instance.id}
              className="bg-theme-surface-hover rounded-lg p-4 border border-theme hover:border-theme-accent/50 transition-colors"
            >
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-3 flex-wrap">
                    <h4 className="font-medium text-theme-primary">{instance.name}</h4>
                    {getStatusBadge(instance.status)}
                    <Badge variant="outline" size="xs">{instance.variety}</Badge>
                  </div>
                  {/* IP Addresses with copy buttons */}
                  <div className="mt-3 flex flex-wrap gap-3">
                    {instance.private_ip_address && (
                      <div className="flex items-center gap-1 bg-theme-surface px-2 py-1 rounded border border-theme">
                        <span className="text-xs text-theme-secondary">Private:</span>
                        <code className="text-sm text-theme-primary font-mono">{instance.private_ip_address}</code>
                        <button
                          onClick={() => copyInstanceIp(instance.private_ip_address!, 'private', instance.id)}
                          className="ml-1 p-0.5 text-theme-secondary hover:text-theme-primary rounded"
                          title="Copy IP"
                        >
                          {copiedField === `${instance.id}-private` ? <Check className="w-3 h-3 text-theme-success" /> : <Copy className="w-3 h-3" />}
                        </button>
                      </div>
                    )}
                    {instance.public_ip_address && (
                      <div className="flex items-center gap-1 bg-theme-surface px-2 py-1 rounded border border-theme">
                        <span className="text-xs text-theme-secondary">Public:</span>
                        <code className="text-sm text-theme-primary font-mono">{instance.public_ip_address}</code>
                        <button
                          onClick={() => copyInstanceIp(instance.public_ip_address!, 'public', instance.id)}
                          className="ml-1 p-0.5 text-theme-secondary hover:text-theme-primary rounded"
                          title="Copy IP"
                        >
                          {copiedField === `${instance.id}-public` ? <Check className="w-3 h-3 text-theme-success" /> : <Copy className="w-3 h-3" />}
                        </button>
                      </div>
                    )}
                    {instance.vpn_ip_address && (
                      <div className="flex items-center gap-1 bg-theme-surface px-2 py-1 rounded border border-theme">
                        <span className="text-xs text-theme-secondary">VPN:</span>
                        <code className="text-sm text-theme-primary font-mono">{instance.vpn_ip_address}</code>
                        <button
                          onClick={() => copyInstanceIp(instance.vpn_ip_address!, 'vpn', instance.id)}
                          className="ml-1 p-0.5 text-theme-secondary hover:text-theme-primary rounded"
                          title="Copy IP"
                        >
                          {copiedField === `${instance.id}-vpn` ? <Check className="w-3 h-3 text-theme-success" /> : <Copy className="w-3 h-3" />}
                        </button>
                      </div>
                    )}
                    {!instance.private_ip_address && !instance.public_ip_address && !instance.vpn_ip_address && (
                      <span className="text-sm text-theme-tertiary italic">No IP addresses assigned</span>
                    )}
                  </div>
                </div>
                {/* Actions */}
                <div className="flex items-center gap-2 ml-4 flex-shrink-0">
                  {canUpdateInstances && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setEditInstance(instance)}
                      title="Edit Instance"
                    >
                      <Edit className="w-4 h-4" />
                    </Button>
                  )}
                  {canDeleteInstances && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setDeleteInstanceConfirm(instance)}
                      title="Delete Instance"
                      className="text-theme-error hover:border-theme-danger"
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  )}
                  {canControlInstances && (
                    <NodeInstanceControls
                      instance={instance}
                      onActionComplete={handleInstanceActionComplete}
                    />
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Delete Instance Confirmation */}
      {deleteInstanceConfirm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-theme-surface rounded-lg p-6 max-w-md mx-4 border border-theme shadow-xl">
            <h3 className="text-lg font-semibold text-theme-primary mb-2">Delete Instance</h3>
            <p className="text-theme-secondary mb-4">
              Are you sure you want to delete <strong>{deleteInstanceConfirm.name}</strong>? This action cannot be undone.
            </p>
            <div className="flex justify-end gap-3">
              <Button
                variant="ghost"
                onClick={() => setDeleteInstanceConfirm(null)}
                disabled={deletingInstance}
              >
                Cancel
              </Button>
              <Button
                variant="danger"
                onClick={handleDeleteInstance}
                disabled={deletingInstance}
              >
                {deletingInstance ? 'Deleting...' : 'Delete'}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );

  const ModulesTab = () => (
    <div className="space-y-4">
      {modules.length === 0 ? (
        <div className="text-center py-8 text-theme-secondary">
          <Box className="w-12 h-12 mx-auto mb-3 opacity-50" />
          <p>No modules assigned</p>
        </div>
      ) : (
        <div className="space-y-2">
          {modules.map(module => (
            <div
              key={module.id}
              className="flex items-center justify-between p-3 bg-theme-surface-hover rounded-lg border border-theme"
            >
              <div className="flex items-center gap-3">
                <Box className="w-5 h-5 text-theme-secondary" />
                <div>
                  <p className="font-medium text-theme-primary">{module.name}</p>
                  {module.category_name && (
                    <p className="text-sm text-theme-secondary">{module.category_name}</p>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-2">
                <Badge variant="outline" size="xs">{module.variety}</Badge>
                <Badge variant={module.enabled ? 'success' : 'secondary'} size="xs">
                  {module.enabled ? 'Enabled' : 'Disabled'}
                </Badge>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  const OperationsTab = () => (
    <div className="space-y-4">
      {operations.length === 0 ? (
        <div className="text-center py-8 text-theme-secondary">
          <Activity className="w-12 h-12 mx-auto mb-3 opacity-50" />
          <p>No operations found</p>
        </div>
      ) : (
        <div className="space-y-3">
          {operations.map(operation => (
            <div
              key={operation.id}
              className="bg-theme-surface-hover rounded-lg p-4 border border-theme"
            >
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <div className="flex items-center gap-3">
                    <h4 className="font-medium text-theme-primary">{operation.command}</h4>
                    {getOperationStatusBadge(operation.status)}
                  </div>
                  {operation.description && (
                    <p className="text-sm text-theme-secondary mt-1">{operation.description}</p>
                  )}
                  {/* Progress bar for running operations */}
                  {operation.status === 'running' && (
                    <div className="mt-2">
                      <div className="flex items-center justify-between text-xs text-theme-secondary mb-1">
                        <span>Progress</span>
                        <span>{operation.progress}%</span>
                      </div>
                      <div className="w-full bg-theme-muted rounded-full h-2">
                        <div
                          className="bg-theme-interactive-primary h-2 rounded-full transition-all duration-300"
                          style={{ width: `${operation.progress}%` }}
                        />
                      </div>
                    </div>
                  )}
                  {/* Error message */}
                  {operation.status === 'failed' && operation.error_message && (
                    <p className="text-sm text-theme-danger mt-2">{operation.error_message}</p>
                  )}
                  <div className="flex items-center gap-4 mt-2 text-xs text-theme-secondary">
                    {operation.started_at && (
                      <span>Started: {new Date(operation.started_at).toLocaleString()}</span>
                    )}
                    {operation.completed_at && (
                      <span>Completed: {new Date(operation.completed_at).toLocaleString()}</span>
                    )}
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  // Build tabs array
  const tabs: Tab[] = [
    {
      id: 'info',
      label: 'Information',
      icon: <Server className="w-4 h-4" />,
      content: <InfoTab />
    }
  ];

  if (canViewInstances) {
    tabs.push({
      id: 'instances',
      label: 'Instances',
      icon: <Cpu className="w-4 h-4" />,
      badge: instances.length,
      content: <InstancesTab />
    });
  }

  if (canViewModules) {
    tabs.push({
      id: 'modules',
      label: 'Modules',
      icon: <Box className="w-4 h-4" />,
      badge: modules.length,
      content: <ModulesTab />
    });
  }

  if (canViewOperations) {
    tabs.push({
      id: 'operations',
      label: 'Operations',
      icon: <Activity className="w-4 h-4" />,
      badge: operations.filter(op => ['pending', 'running'].includes(op.status)).length || undefined,
      content: <OperationsTab />
    });
  }

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title={node?.name || 'Node Details'}
        subtitle={node?.node_template_name ? `Template: ${node.node_template_name}` : undefined}
        icon={<Server className="w-6 h-6" />}
        size="4xl"
        footer={
          <div className="flex items-center gap-3">
            {canUpdateNode && node && (
              <Button
                variant="secondary"
                onClick={() => setShowEditModal(true)}
              >
                Edit Node
              </Button>
            )}
            <Button variant="ghost" onClick={onClose}>
              Close
            </Button>
          </div>
        }
      >
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner size="lg" />
          </div>
        ) : node ? (
          <TabContainer
            tabs={tabs}
            activeTab={activeTab}
            onTabChange={setActiveTab}
            variant="underline"
          />
        ) : (
          <div className="text-center py-8 text-theme-secondary">
            <Server className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p>Node not found</p>
          </div>
        )}
      </Modal>

      {/* Edit Node Modal */}
      <EditNodeModal
        node={node}
        isOpen={showEditModal}
        onClose={() => setShowEditModal(false)}
        onNodeUpdated={handleNodeEditComplete}
      />

      {/* Create Instance Modal */}
      <CreateInstanceModal
        node={node}
        isOpen={showCreateInstanceModal}
        onClose={() => setShowCreateInstanceModal(false)}
        onInstanceCreated={handleInstanceCreated}
      />

      {/* Edit Instance Modal */}
      <EditInstanceModal
        nodeId={nodeId}
        instance={editInstance}
        isOpen={!!editInstance}
        onClose={() => setEditInstance(null)}
        onInstanceUpdated={handleInstanceEditComplete}
      />
    </>
  );
};

export default NodeDetailModal;
