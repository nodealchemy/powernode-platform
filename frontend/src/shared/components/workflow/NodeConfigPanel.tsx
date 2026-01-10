import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Node } from '@xyflow/react';
import {
  X,
  Save,
  Trash2,
  AlertTriangle,
  CheckCircle,
  Info,
  ShieldAlert,
  GitBranch
} from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Button } from '@/shared/components/ui/Button';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { agentsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import type { AiAgent } from '@/shared/types/ai';
import type { HandlePosition, HandlePositions } from './nodes/DynamicNodeHandles';
import { getHandleIdsForNodeType, getDefaultHandlePositions } from './nodes/DynamicNodeHandles';
import { getNodeTypeConfig, positionOptions } from './config/node-types';
import type { NodeConfiguration } from './config/node-types';

// Define the workflow node data structure
export interface WorkflowNodeData {
  name?: string;
  description?: string;
  isStartNode?: boolean;
  isEndNode?: boolean;
  isErrorHandler?: boolean;
  timeoutSeconds?: number;
  retryCount?: number;
  handlePositions?: HandlePositions;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  configuration?: Record<string, any>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  metadata?: Record<string, any>;
  _handleUpdateTimestamp?: number;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  [key: string]: any;
}

export interface NodeConfigPanelProps {
  node: Node<WorkflowNodeData>;
  onUpdate: (nodeId: string, updates: Partial<WorkflowNodeData>) => void;
  onClose: () => void;
  onDelete?: (nodeId: string) => void;
  className?: string;
}

// Response structure for agent list API
interface AgentListResponse {
  items?: AiAgent[];
  agents?: AiAgent[];
  data?: {
    agents?: AiAgent[];
    data?: { agents?: AiAgent[] };
  };
}

// Helper function to extract agent list from various response structures
const extractAgentList = (response: AgentListResponse | AiAgent[] | unknown): AiAgent[] => {
  if (Array.isArray(response)) {
    return response as AiAgent[];
  }
  if (response && typeof response === 'object') {
    const resp = response as AgentListResponse;
    if (resp.items && Array.isArray(resp.items)) {
      return resp.items;
    }
    if (resp.data?.data?.agents && Array.isArray(resp.data.data.agents)) {
      return resp.data.data.agents;
    } else if (resp.data?.agents && Array.isArray(resp.data.agents)) {
      return resp.data.agents;
    } else if (resp.agents && Array.isArray(resp.agents)) {
      return resp.agents;
    }
  }
  return [];
};

// Get node type display info
const getNodeTypeInfo = (nodeType: string) => {
  const typeMap: Record<string, { label: string; color: string; icon: string }> = {
    trigger: { label: 'Trigger', color: 'text-theme-success', icon: '⚡' },
    ai_agent: { label: 'AI Agent', color: 'text-theme-interactive-primary', icon: '🤖' },
    api_call: { label: 'API Call', color: 'text-theme-info', icon: '🌐' },
    condition: { label: 'Condition', color: 'text-theme-warning', icon: '🔀' },
    transform: { label: 'Transform', color: 'text-theme-cyan', icon: '🔄' },
    start: { label: 'Start', color: 'text-theme-success', icon: '▶️' },
    end: { label: 'End', color: 'text-theme-error', icon: '⏹️' },
    loop: { label: 'Loop', color: 'text-theme-info', icon: '🔁' },
    merge: { label: 'Merge', color: 'text-theme-warning', icon: '🔗' },
    split: { label: 'Split', color: 'text-theme-warning', icon: '🔀' },
    webhook: { label: 'Webhook', color: 'text-theme-info', icon: '🔔' },
    database: { label: 'Database', color: 'text-theme-info', icon: '💾' },
    email: { label: 'Email', color: 'text-theme-info', icon: '📧' },
    notification: { label: 'Notification', color: 'text-theme-info', icon: '🔔' },
    human_approval: { label: 'Human Approval', color: 'text-theme-warning', icon: '👤' },
    sub_workflow: { label: 'Sub-Workflow', color: 'text-theme-info', icon: '📋' },
    kb_article: { label: 'KB Article', color: 'text-theme-info', icon: '📝' },
    page: { label: 'Page', color: 'text-theme-info', icon: '📄' },
    mcp_tool: { label: 'MCP Tool', color: 'text-theme-info', icon: '🔧' },
    mcp_resource: { label: 'MCP Resource', color: 'text-theme-info', icon: '📦' },
    mcp_prompt: { label: 'MCP Prompt', color: 'text-theme-info', icon: '💬' },
    mcp_operation: { label: 'MCP Operation', color: 'text-theme-info', icon: '⚙️' },
  };
  return typeMap[nodeType] || { label: nodeType, color: 'text-theme-secondary', icon: '⚙️' };
};

export const NodeConfigPanel: React.FC<NodeConfigPanelProps> = ({
  node,
  onUpdate,
  onClose,
  onDelete,
  className = ''
}) => {
  const { isAuthenticated } = useAuth();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [loadingAgents, setLoadingAgents] = useState(false);
  const agentsLoadedRef = useRef(false);
  const loadingAgentsRef = useRef(false);
  const currentNodeRef = useRef(node.id);

  // Compute initial handlePositions
  const initialHandlePositions = node.data?.handlePositions ||
    getDefaultHandlePositions(node.type || 'default', node.data?.isStartNode, node.data?.isEndNode);

  const [config, setConfig] = useState<NodeConfiguration>({
    name: node.data?.name || '',
    description: node.data?.description || '',
    isStartNode: node.data?.isStartNode || false,
    isEndNode: node.data?.isEndNode || false,
    isErrorHandler: node.data?.isErrorHandler || false,
    timeoutSeconds: node.data?.timeoutSeconds || 300,
    retryCount: node.data?.retryCount || 0,
    handlePositions: initialHandlePositions,
    configuration: node.data?.configuration || {},
    metadata: node.data?.metadata || {}
  });

  const [activeTab, setActiveTab] = useState('basic');
  const [hasChanges, setHasChanges] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});

  // Load agents for AI agent nodes
  const loadAvailableAgents = useCallback(async () => {
    if (loadingAgentsRef.current || agentsLoadedRef.current) return;
    if (!isAuthenticated) return;

    loadingAgentsRef.current = true;
    setLoadingAgents(true);

    try {
      const response = await agentsApi.getAgents({ status: 'active', per_page: 100 });
      const agentList = extractAgentList(response);
      setAgents(agentList);
      agentsLoadedRef.current = true;
    } catch (error: unknown) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load available agents:', error);
      }
      setAgents([]);
      const isAuthError = (
        error !== null &&
        typeof error === 'object' &&
        'response' in error &&
        typeof (error as { response?: { status?: number } }).response?.status === 'number' &&
        ((error as { response: { status: number } }).response.status === 401 ||
         (error as { response: { status: number } }).response.status === 403)
      );
      if (!isAuthError) {
        agentsLoadedRef.current = true;
      }
    } finally {
      loadingAgentsRef.current = false;
      setLoadingAgents(false);
    }
  }, [isAuthenticated]);

  // Initialize agents for AI agent nodes
  useEffect(() => {
    if (node.type === 'ai_agent' && isAuthenticated && !agentsLoadedRef.current && !loadingAgentsRef.current) {
      loadAvailableAgents();
    }
  }, [node.type, isAuthenticated, loadAvailableAgents]);

  // Fetch individual agent details if needed
  const fetchAgentDetails = useCallback(async (agentId: string) => {
    if (!agentId || loadingAgentsRef.current) return;

    loadingAgentsRef.current = true;
    setLoadingAgents(true);

    try {
      const response = await agentsApi.getAgent(agentId);
      if (response) {
        setAgents(prev => {
          const existingAgent = prev.find(a => a.id === agentId);
          if (existingAgent) return prev;
          return [...prev, response];
        });
      }
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to fetch agent details for ID:', agentId, error);
      }
      setAgents(prev => {
        const existingAgent = prev.find(a => a.id === agentId);
        if (existingAgent) return prev;
        return [...prev, {
          id: agentId,
          name: 'Agent details unavailable',
          status: 'unknown',
          error: 'Failed to load agent details'
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        } as any];
      });
    } finally {
      loadingAgentsRef.current = false;
      setLoadingAgents(false);
    }
  }, []);

  // Fetch agent if not in list
  useEffect(() => {
    const agentId = node.data?.configuration?.agent_id;
    if (node.type === 'ai_agent' && agentId && isAuthenticated && agents.length > 0) {
      const agentExists = agents.find(a => a.id === agentId);
      if (!agentExists && !loadingAgentsRef.current) {
        fetchAgentDetails(agentId);
      }
    }
  }, [node.type, node.data?.configuration?.agent_id, agents, isAuthenticated, fetchAgentDetails]);

  // Update config when node changes
  useEffect(() => {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { _handleUpdateTimestamp: _temp, ...cleanNodeData } = node.data || {};

    setConfig({
      name: cleanNodeData.name || '',
      description: cleanNodeData.description || '',
      isStartNode: cleanNodeData.isStartNode || false,
      isEndNode: cleanNodeData.isEndNode || false,
      isErrorHandler: cleanNodeData.isErrorHandler || false,
      timeoutSeconds: cleanNodeData.timeoutSeconds || 300,
      retryCount: cleanNodeData.retryCount || 0,
      handlePositions: cleanNodeData.handlePositions ||
        getDefaultHandlePositions(node.type || 'default', cleanNodeData.isStartNode, cleanNodeData.isEndNode),
      configuration: cleanNodeData.configuration || {},
      metadata: cleanNodeData.metadata || {}
    });

    setErrors({});
    setActiveTab('basic');
    setHasChanges(false);

    const nodeChanged = currentNodeRef.current !== node.id;
    if (nodeChanged) {
      currentNodeRef.current = node.id;
      if (node.type !== 'ai_agent') {
        agentsLoadedRef.current = false;
        loadingAgentsRef.current = false;
        setAgents([]);
        setLoadingAgents(false);
      } else {
        agentsLoadedRef.current = false;
        loadingAgentsRef.current = false;
        setLoadingAgents(false);
      }
    }
  }, [node.id, node.type, node.data]);

  const markAsChanged = () => {
    if (!hasChanges) setHasChanges(true);
  };

  const validateConfig = () => {
    const newErrors: Record<string, string> = {};
    if (!config.name.trim()) {
      newErrors.name = 'Node name is required';
    }
    if (config.timeoutSeconds < 1) {
      newErrors.timeoutSeconds = 'Timeout must be at least 1 second';
    }
    if (config.retryCount < 0) {
      newErrors.retryCount = 'Retry count cannot be negative';
    }
    if (node.type === 'ai_agent') {
      if (!config.configuration?.agent_id) {
        newErrors.agent = 'Agent selection is required';
      }
    }
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleFieldChange = (field: keyof NodeConfiguration, value: any) => {
    setConfig(prev => ({ ...prev, [field]: value }));
    markAsChanged();
    if (errors[field]) {
      setErrors(prev => {
        const newErrors = { ...prev };
        delete newErrors[field];
        return newErrors;
      });
    }
  };

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleConfigChange = (key: string, value: any) => {
    setConfig(prev => ({
      ...prev,
      configuration: { ...prev.configuration, [key]: value }
    }));
    markAsChanged();
  };

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleMetadataChange = (key: string, value: any) => {
    setConfig(prev => ({
      ...prev,
      metadata: { ...prev.metadata, [key]: value }
    }));
    markAsChanged();
  };

  const handleAgentChange = (agentId: string) => {
    const selectedAgent = agents.find(a => a.id === agentId);
    if (selectedAgent) {
      const updatedConfig = {
        ...config.configuration,
        agent_id: agentId,
        agent_name: selectedAgent.name,
        model: selectedAgent.mcp_metadata?.model_config?.model || config.configuration.model,
        provider: selectedAgent.ai_provider?.slug || config.configuration.provider
      };
      setConfig(prev => ({ ...prev, configuration: updatedConfig }));
      markAsChanged();
    }
  };

  const handleSave = () => {
    if (!validateConfig()) return;

    const updateData: Record<string, unknown> = {
      name: config.name,
      description: config.description,
      isStartNode: config.isStartNode,
      isEndNode: config.isEndNode,
      isErrorHandler: config.isErrorHandler,
      timeoutSeconds: config.timeoutSeconds,
      retryCount: config.retryCount,
      handlePositions: config.handlePositions,
      configuration: config.configuration,
      metadata: config.metadata
    };

    onUpdate(node.id, updateData);
    setHasChanges(false);
  };

  const handleDelete = () => {
    if (onDelete) {
      confirm({
        title: 'Delete Node',
        message: `Are you sure you want to delete the node "${config.name}"?`,
        confirmLabel: 'Delete',
        variant: 'danger',
        onConfirm: async () => {
          onDelete(node.id);
          onClose();
        }
      });
    }
  };

  // Build handle positions config UI
  const handleDefs = getHandleIdsForNodeType(
    node.type || 'default',
    node.data?.isStartNode || node.type === 'start',
    node.data?.isEndNode || node.type === 'end'
  );

  const currentPositions: HandlePositions = config.handlePositions ||
    getDefaultHandlePositions(node.type || 'default', node.data?.isStartNode, node.data?.isEndNode);

  const handlePositionChange = (handleId: string, position: HandlePosition) => {
    const updatedPositions = { ...currentPositions, [handleId]: position };
    setConfig(prev => ({ ...prev, handlePositions: updatedPositions }));
    markAsChanged();
  };

  const handlePositionsConfig = (
    <div className="mb-6">
      <h4 className="text-sm font-medium text-theme-primary mb-3">Handle Positions</h4>
      <div className="space-y-3">
        {handleDefs.map((handle) => (
          <EnhancedSelect
            key={handle.id}
            label={`${handle.label} (${handle.type})`}
            value={currentPositions[handle.id] || 'bottom'}
            onChange={(value) => handlePositionChange(handle.id, value as HandlePosition)}
            options={positionOptions}
          />
        ))}
      </div>
      <p className="text-xs text-theme-muted mt-2">
        Configure where each connection handle appears on the node.
      </p>
    </div>
  );

  // Get the appropriate config component for this node type
  const NodeTypeConfigComponent = getNodeTypeConfig(node.type || 'default');
  const nodeTypeInfo = getNodeTypeInfo(node.type || 'unknown');

  return (
    <div className={`
      fixed right-4 top-4 bottom-4 w-96 bg-theme-surface border border-theme
      rounded-lg shadow-2xl z-50 flex flex-col
      ${className}
    `}>
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-theme">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <span className="text-lg">{nodeTypeInfo.icon}</span>
            <div>
              <h3 className="font-semibold text-theme-primary">Configure Node</h3>
              <p className={`text-sm ${nodeTypeInfo.color}`}>
                {nodeTypeInfo.label}
              </p>
            </div>
          </div>
          {hasChanges && (
            <div className="flex items-center gap-1 text-theme-warning">
              <AlertTriangle className="h-4 w-4" />
              <span className="text-xs">Unapplied</span>
            </div>
          )}
        </div>
        <button
          onClick={onClose}
          className="p-2 rounded-lg text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        <Tabs value={activeTab} onValueChange={setActiveTab} defaultValue="basic" className="h-full flex flex-col">
          <TabsList className="m-4 mb-0">
            <TabsTrigger value="basic">Basic</TabsTrigger>
            <TabsTrigger value="config">Config</TabsTrigger>
            <TabsTrigger value="advanced">Advanced</TabsTrigger>
          </TabsList>

          <div className="flex-1 overflow-y-auto custom-scrollbar p-4">
            <TabsContent value="basic" className="space-y-4 mt-0">
              <Input
                label="Node Name"
                value={config.name}
                onChange={(e) => handleFieldChange('name', e.target.value)}
                placeholder="Enter node name..."
                error={errors.name}
                required
              />

              <Textarea
                label="Description"
                value={config.description}
                onChange={(e) => handleFieldChange('description', e.target.value)}
                placeholder="Describe what this node does..."
                rows={3}
              />

              {/* Node Role Configuration */}
              <div className="space-y-4">
                <div>
                  <h4 className="text-sm font-medium text-theme-primary mb-3">Node Role in Workflow</h4>

                  <div className="grid grid-cols-1 gap-3 mb-4">
                    {(config.isStartNode || node.type === 'trigger' || node.type === 'start') && (
                      <div className="flex items-center gap-3 p-3 rounded-lg border border-theme-success/30 bg-theme-success/10">
                        <CheckCircle className="h-4 w-4 text-theme-success" />
                        <div className="flex-1">
                          <span className="text-sm font-medium text-theme-success">Start Node</span>
                          <p className="text-xs text-theme-success/80 mt-1">
                            Entry point for workflow execution. Use workflow canvas controls to modify.
                          </p>
                        </div>
                      </div>
                    )}

                    {(config.isEndNode || node.type === 'end') && (
                      <div className="flex items-center gap-3 p-3 rounded-lg border border-theme-info/30 bg-theme-info/10">
                        <CheckCircle className="h-4 w-4 text-theme-info" />
                        <div className="flex-1">
                          <span className="text-sm font-medium text-theme-info">End Node</span>
                          <p className="text-xs text-theme-info/80 mt-1">
                            Terminal point in workflow execution. Use workflow canvas controls to modify.
                          </p>
                        </div>
                      </div>
                    )}

                    {!config.isStartNode && !config.isEndNode && node.type !== 'start' && node.type !== 'trigger' && node.type !== 'end' && (
                      <div className="flex items-center gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                        <Info className="h-4 w-4 text-theme-muted" />
                        <div className="flex-1">
                          <span className="text-sm font-medium text-theme-primary">Processing Node</span>
                          <p className="text-xs text-theme-muted mt-1">
                            Intermediate processing step. Use right-click menu to set as start/end node.
                          </p>
                        </div>
                      </div>
                    )}
                  </div>

                  {/* Error Handler Configuration */}
                  <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                    <input
                      type="checkbox"
                      checked={config.isErrorHandler}
                      onChange={(e) => handleFieldChange('isErrorHandler', e.target.checked)}
                      className="mt-0.5 rounded border-theme-border"
                    />
                    <div className="flex-1">
                      <label className="text-sm font-medium text-theme-primary">
                        Error Handler
                      </label>
                      <p className="text-xs text-theme-muted mt-1">
                        Processes errors from other nodes. Provides fault tolerance and error recovery.
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </TabsContent>

            <TabsContent value="config" className="space-y-4 mt-0">
              <NodeTypeConfigComponent
                config={config}
                handleConfigChange={handleConfigChange}
                handlePositionsConfig={handlePositionsConfig}
                markAsChanged={markAsChanged}
                agents={agents}
                loadingAgents={loadingAgents}
                handleAgentChange={handleAgentChange}
                fetchAgentDetails={fetchAgentDetails}
              />
            </TabsContent>

            <TabsContent value="advanced" className="space-y-6 mt-0">
              {/* Execution Settings */}
              <div>
                <h4 className="text-sm font-medium text-theme-primary mb-3 flex items-center gap-2">
                  <ShieldAlert className="h-4 w-4" />
                  Execution Settings
                </h4>
                <div className="space-y-3">
                  <Input
                    label="Timeout (seconds)"
                    type="number"
                    value={config.timeoutSeconds}
                    onChange={(e) => handleFieldChange('timeoutSeconds', parseInt(e.target.value) || 300)}
                    min={1}
                    error={errors.timeoutSeconds}
                    description="Maximum time allowed for node execution"
                  />

                  <Input
                    label="Retry Count"
                    type="number"
                    value={config.retryCount}
                    onChange={(e) => handleFieldChange('retryCount', parseInt(e.target.value) || 0)}
                    min={0}
                    max={5}
                    error={errors.retryCount}
                    description="Number of automatic retries on failure"
                  />
                </div>
              </div>

              {/* Workflow Control */}
              <div>
                <h4 className="text-sm font-medium text-theme-primary mb-3 flex items-center gap-2">
                  <GitBranch className="h-4 w-4" />
                  Workflow Control
                </h4>
                <div className="space-y-3">
                  <Checkbox
                    label="Continue on Error"
                    description="Continue workflow execution even if this node fails"
                    checked={config.metadata?.continue_on_error === true}
                    onCheckedChange={(checked) => handleMetadataChange('continue_on_error', checked)}
                  />

                  <Checkbox
                    label="Requires Approval"
                    description="Pause workflow and wait for manual approval before executing"
                    checked={config.metadata?.requires_approval === true}
                    onCheckedChange={(checked) => handleMetadataChange('requires_approval', checked)}
                  />
                </div>
              </div>

              {/* Conditional Execution */}
              <div>
                <Input
                  label="Condition Expression"
                  value={config.metadata?.condition || ''}
                  onChange={(e) => handleMetadataChange('condition', e.target.value || null)}
                  placeholder="${{ steps.previous.outputs.success == true }}"
                  description="Expression that must evaluate to true for this node to execute"
                />
              </div>

              {/* Raw Metadata */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Raw Metadata (JSON)
                </label>
                <Textarea
                  value={JSON.stringify(config.metadata, null, 2)}
                  onChange={(e) => {
                    try {
                      const parsed = JSON.parse(e.target.value);
                      handleFieldChange('metadata', parsed);
                    } catch {
                      // Invalid JSON, don't update
                    }
                  }}
                  rows={6}
                  placeholder="Enter JSON metadata..."
                  className="font-mono text-sm"
                />
                <p className="text-xs text-theme-muted mt-1">
                  Edit raw metadata JSON. Changes here will sync with the fields above.
                </p>
              </div>
            </TabsContent>
          </div>
        </Tabs>
      </div>

      {/* Footer */}
      <div className="flex items-center justify-between p-4 border-t border-theme">
        <div className="flex gap-2">
          {onDelete && (
            <Button
              variant="outline"
              onClick={handleDelete}
              className="text-theme-error hover:text-white hover:bg-theme-error"
            >
              <Trash2 className="h-4 w-4 mr-2" />
              Delete
            </Button>
          )}
        </div>

        <div className="flex gap-2">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button
            onClick={handleSave}
            disabled={!hasChanges || Object.keys(errors).length > 0}
          >
            <Save className="h-4 w-4 mr-2" />
            Apply Changes
          </Button>
        </div>
      </div>

      {/* Validation Summary */}
      {Object.keys(errors).length > 0 && (
        <div className="mx-4 mb-4 p-3 bg-theme-error-background border border-theme-error rounded-lg">
          <div className="flex items-center gap-2 text-theme-error text-sm font-medium mb-2">
            <AlertTriangle className="h-4 w-4" />
            Configuration Errors
          </div>
          <ul className="text-sm text-theme-error space-y-1">
            {Object.values(errors).map((error, index) => (
              <li key={index}>• {error}</li>
            ))}
          </ul>
        </div>
      )}
      {ConfirmationDialog}
    </div>
  );
};
