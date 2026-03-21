import React, { useState, useEffect, useCallback } from 'react';
import { X, FileText, Server, Package, Settings, Globe, Lock, User, Calendar, Edit2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { systemApi } from '@/features/system/services/systemApi';
import { useSystemWebSocket, type NodeUpdatePayload } from '@/features/system/hooks/useSystemWebSocket';
import type { SystemNodeTemplate, SystemNode, SystemNodeModule } from '@/features/system/types/system.types';

interface TemplateDetailModalProps {
  /** The template ID to display */
  templateId: string | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when template is updated */
  onTemplateUpdated?: () => void;
  /** Callback when edit is requested */
  onEdit?: (template: SystemNodeTemplate) => void;
}

/**
 * TemplateDetailModal - Multi-tab modal showing template details
 *
 * Tabs:
 * - Info: Basic template information
 * - Nodes: Nodes using this template
 * - Modules: Modules assigned to this template
 * - Config: Template configuration
 */
export const TemplateDetailModal: React.FC<TemplateDetailModalProps> = ({
  templateId,
  isOpen,
  onClose,
  onTemplateUpdated: _onTemplateUpdated,
  onEdit
}) => {
  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();
  const canEdit = hasPermission('system.templates.update');

  // State
  const [template, setTemplate] = useState<SystemNodeTemplate | null>(null);
  const [nodes, setNodes] = useState<SystemNode[]>([]);
  const [modules, setModules] = useState<SystemNodeModule[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('info');

  // Fetch template details
  const fetchTemplate = useCallback(async () => {
    if (!templateId) return;

    try {
      const templateData = await systemApi.getTemplate(templateId);
      setTemplate(templateData);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load template details'
      });
    }
  }, [templateId, addNotification]);

  // Fetch nodes using this template
  const fetchNodes = useCallback(async () => {
    if (!templateId) return;

    try {
      const result = await systemApi.getNodes({ per_page: 100 });
      // Filter nodes that use this template
      const templateNodes = result.nodes.filter(node => node.node_template_id === templateId);
      setNodes(templateNodes);
    } catch (error) {
      // Non-critical error
      if (process.env.NODE_ENV === 'development') {
        console.warn('Failed to fetch template nodes:', error);
      }
    }
  }, [templateId]);

  // WebSocket for real-time updates - refresh nodes when a node using this template is updated
  useSystemWebSocket({
    onNodeUpdate: useCallback((_updatedNode: NodeUpdatePayload) => {
      // Note: NodeUpdatePayload doesn't include node_template_id, so we always refresh for any node update
      // The fetchNodes function will filter to only show nodes that use this template
      fetchNodes();
    }, [fetchNodes])
  });

  // Fetch modules assigned to this template
  const fetchModules = useCallback(async () => {
    if (!templateId) return;

    try {
      const result = await systemApi.getTemplateModules(templateId);
      setModules(result.modules);
    } catch (error) {
      // Non-critical error
      if (process.env.NODE_ENV === 'development') {
        console.warn('Failed to fetch template modules:', error);
      }
    }
  }, [templateId]);

  // Load data when modal opens
  useEffect(() => {
    if (isOpen && templateId) {
      setLoading(true);
      setActiveTab('info');

      Promise.all([
        fetchTemplate(),
        fetchNodes(),
        fetchModules()
      ]).finally(() => {
        setLoading(false);
      });
    }
  }, [isOpen, templateId, fetchTemplate, fetchNodes, fetchModules]);

  // Reset when closed
  useEffect(() => {
    if (!isOpen) {
      setTemplate(null);
      setNodes([]);
      setModules([]);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  // Format date
  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  // Tab content components
  const InfoTab = () => (
    <div className="space-y-6">
      {/* Basic Info */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-2 text-theme-secondary text-sm mb-1">
            <FileText className="w-4 h-4" />
            Name
          </div>
          <div className="text-theme-primary font-medium">{template?.name}</div>
        </div>

        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-2 text-theme-secondary text-sm mb-1">
            <Settings className="w-4 h-4" />
            Platform
          </div>
          <div className="text-theme-primary">{template?.node_platform_name || '-'}</div>
        </div>

        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-2 text-theme-secondary text-sm mb-1">
            <User className="w-4 h-4" />
            Admin User
          </div>
          <div className="text-theme-primary font-mono">{template?.admin_user || 'root'}</div>
        </div>

        <div className="bg-theme-background rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-2 text-theme-secondary text-sm mb-1">
            <Server className="w-4 h-4" />
            Nodes Using Template
          </div>
          <div className="text-theme-primary font-medium">{template?.node_count || 0}</div>
        </div>
      </div>

      {/* Status Badges */}
      <div className="flex items-center gap-4">
        <div>
          <span className="text-theme-secondary text-sm mr-2">Status:</span>
          <Badge
            variant={template?.enabled ? 'success' : 'secondary'}
            dot
            pulse={template?.enabled}
          >
            {template?.enabled ? 'Enabled' : 'Disabled'}
          </Badge>
        </div>
        <div>
          <span className="text-theme-secondary text-sm mr-2">Visibility:</span>
          <Badge variant={template?.public ? 'info' : 'secondary'}>
            {template?.public ? (
              <><Globe className="w-3 h-3 mr-1" />Public</>
            ) : (
              <><Lock className="w-3 h-3 mr-1" />Private</>
            )}
          </Badge>
        </div>
      </div>

      {/* Description */}
      {template?.description && (
        <div>
          <h4 className="text-theme-primary font-medium mb-2">Description</h4>
          <p className="text-theme-secondary bg-theme-background rounded-lg p-4 border border-theme">
            {template.description}
          </p>
        </div>
      )}

      {/* Timestamps */}
      <div className="flex items-center gap-6 text-sm text-theme-tertiary">
        <div className="flex items-center gap-1">
          <Calendar className="w-4 h-4" />
          Created: {template?.created_at ? formatDate(template.created_at) : '-'}
        </div>
        <div className="flex items-center gap-1">
          <Calendar className="w-4 h-4" />
          Updated: {template?.updated_at ? formatDate(template.updated_at) : '-'}
        </div>
      </div>
    </div>
  );

  const NodesTab = () => (
    <div className="space-y-4">
      {nodes.length === 0 ? (
        <div className="text-center py-8 text-theme-secondary">
          <Server className="w-12 h-12 mx-auto mb-2 opacity-50" />
          <p>No nodes are using this template</p>
        </div>
      ) : (
        <div className="space-y-2">
          {nodes.map((node) => (
            <div
              key={node.id}
              className="bg-theme-background rounded-lg p-4 border border-theme flex items-center justify-between"
            >
              <div className="flex items-center gap-3">
                <Server className="w-5 h-5 text-theme-tertiary" />
                <div>
                  <div className="font-medium text-theme-primary">{node.name}</div>
                  {node.description && (
                    <div className="text-sm text-theme-secondary">{node.description}</div>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-4">
                <Badge
                  variant={node.enabled ? 'success' : 'secondary'}
                  size="sm"
                  dot
                >
                  {node.enabled ? 'Enabled' : 'Disabled'}
                </Badge>
                <span className="text-theme-secondary text-sm">
                  {node.instance_count || 0} instances
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  const ModulesTab = () => (
    <div className="space-y-4">
      {modules.length === 0 ? (
        <div className="text-center py-8 text-theme-secondary">
          <Package className="w-12 h-12 mx-auto mb-2 opacity-50" />
          <p>No modules assigned to this template</p>
        </div>
      ) : (
        <div className="space-y-2">
          {modules.map((module) => (
            <div
              key={module.id}
              className="bg-theme-background rounded-lg p-4 border border-theme flex items-center justify-between"
            >
              <div className="flex items-center gap-3">
                <Package className="w-5 h-5 text-theme-tertiary" />
                <div>
                  <div className="font-medium text-theme-primary">{module.name}</div>
                  {module.description && (
                    <div className="text-sm text-theme-secondary">{module.description}</div>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-4">
                <Badge variant="info" size="sm">
                  {module.variety}
                </Badge>
                <Badge
                  variant={module.enabled ? 'success' : 'secondary'}
                  size="sm"
                  dot
                >
                  {module.enabled ? 'Enabled' : 'Disabled'}
                </Badge>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  const ConfigTab = () => (
    <div className="space-y-4">
      <h4 className="text-theme-primary font-medium">Template Configuration</h4>
      {template?.config && Object.keys(template.config).length > 0 ? (
        <pre className="bg-theme-background rounded-lg p-4 border border-theme overflow-auto text-sm text-theme-primary">
          {JSON.stringify(template.config, null, 2)}
        </pre>
      ) : (
        <div className="text-center py-8 text-theme-secondary">
          <Settings className="w-12 h-12 mx-auto mb-2 opacity-50" />
          <p>No custom configuration defined</p>
        </div>
      )}
    </div>
  );

  const tabs = [
    { id: 'info', label: 'Information', content: <InfoTab /> },
    { id: 'nodes', label: `Nodes (${nodes.length})`, content: <NodesTab /> },
    { id: 'modules', label: `Modules (${modules.length})`, content: <ModulesTab /> },
    { id: 'config', label: 'Configuration', content: <ConfigTab /> }
  ];

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/50 transition-opacity"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-4xl bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <FileText className="w-6 h-6 text-theme-accent" />
              <div>
                <h2 className="text-lg font-semibold text-theme-primary">
                  {loading ? 'Loading...' : template?.name || 'Template Details'}
                </h2>
                {template?.description && (
                  <p className="text-sm text-theme-secondary truncate max-w-md">
                    {template.description}
                  </p>
                )}
              </div>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          {/* Content */}
          <div className="p-4 min-h-[400px]">
            {loading ? (
              <div className="flex items-center justify-center h-64">
                <LoadingSpinner size="lg" />
              </div>
            ) : template ? (
              <TabContainer
                tabs={tabs}
                activeTab={activeTab}
                onTabChange={setActiveTab}
              />
            ) : (
              <div className="flex items-center justify-center h-64 text-theme-secondary">
                Template not found
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex justify-end gap-3 p-4 border-t border-theme">
            <Button variant="outline" onClick={onClose}>
              Close
            </Button>
            {canEdit && onEdit && template && (
              <Button
                variant="primary"
                onClick={() => onEdit(template)}
              >
                <Edit2 className="w-4 h-4 mr-2" />
                Edit Template
              </Button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default TemplateDetailModal;
