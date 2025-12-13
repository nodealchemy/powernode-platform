import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Node } from '@xyflow/react';
import {
  X,
  Settings,
  Save,
  Trash2,
  Info,
  AlertTriangle,
  CheckCircle
} from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Button } from '@/shared/components/ui/Button';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { agentsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import type { AiAgent } from '@/shared/types/ai';
// MCP Config Panels
import { McpToolConfigPanel } from './config/McpToolConfigPanel';
import { McpResourceConfigPanel } from './config/McpResourceConfigPanel';
import { McpPromptConfigPanel } from './config/McpPromptConfigPanel';

import type { HandlePosition, HandlePositions } from './nodes/DynamicNodeHandles';
import { getHandleIdsForNodeType, getDefaultHandlePositions } from './nodes/DynamicNodeHandles';

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
  [key: string]: any; // Allow additional properties for dynamic node types
}

export interface NodeConfigPanelProps {
  node: Node<WorkflowNodeData>;
  onUpdate: (nodeId: string, updates: Partial<WorkflowNodeData>) => void;
  onClose: () => void;
  onDelete?: (nodeId: string) => void;
  className?: string;
}

interface NodeConfiguration {
  name: string;
  description: string;
  isStartNode: boolean;
  isEndNode: boolean;
  isErrorHandler: boolean;
  timeoutSeconds: number;
  retryCount: number;
  handlePositions?: HandlePositions;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  configuration: Record<string, any>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  metadata: Record<string, any>;
}

export const NodeConfigPanel: React.FC<NodeConfigPanelProps> = ({
  node,
  onUpdate,
  onClose,
  onDelete,
  className = ''
}) => {
  const { isAuthenticated } = useAuth();
  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [loadingAgents, setLoadingAgents] = useState(false);
  const agentsLoadedRef = useRef(false);
  const loadingAgentsRef = useRef(false);
  const currentNodeRef = useRef(node.id);
  // Compute initial handlePositions - only from data.handlePositions or defaults
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

  // Response structure for agent list API - handles various response formats
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
    // Handle direct array
    if (Array.isArray(response)) {
      return response as AiAgent[];
    }
    // Handle object responses
    if (response && typeof response === 'object') {
      const resp = response as AgentListResponse;
      // Handle paginated response format (items array)
      if (resp.items && Array.isArray(resp.items)) {
        return resp.items;
      }
      // Handle nested response structures
      if (resp.data?.data?.agents && Array.isArray(resp.data.data.agents)) {
        return resp.data.data.agents;
      } else if (resp.data?.agents && Array.isArray(resp.data.agents)) {
        return resp.data.agents;
      } else if (resp.agents && Array.isArray(resp.agents)) {
        return resp.agents;
      }
    }
    // Return empty array if no valid structure found
    return [];
  };

  const loadAvailableAgents = useCallback(async () => {
    if (loadingAgentsRef.current || agentsLoadedRef.current) {
      return;
    }

    if (!isAuthenticated) {
      return;
    }

    loadingAgentsRef.current = true;
    setLoadingAgents(true);

    try {
      const response = await agentsApi.getAgents({
        status: 'active',
        per_page: 100
      });

      // Extract agent list from various response structures
      const agentList = extractAgentList(response);

      setAgents(agentList);
      agentsLoadedRef.current = true;
    } catch (error: unknown) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load available agents:', error);
      }

      // Set empty array but mark as loaded to prevent infinite retries
      setAgents([]);

      // If authentication error, don't mark as loaded so it can retry when user logs in
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
  }, [node.type, isAuthenticated]);

  // Initialize agents when component mounts for AI agent nodes
  useEffect(() => {
    if (node.type === 'ai_agent' && isAuthenticated && !agentsLoadedRef.current && !loadingAgentsRef.current) {
      loadAvailableAgents();
    }
  }, [node.type, isAuthenticated, loadAvailableAgents]);

  const fetchAgentDetails = useCallback(async (agentId: string) => {
    if (!agentId || loadingAgentsRef.current) return;

    loadingAgentsRef.current = true;
    setLoadingAgents(true);

    try {
      const response = await agentsApi.getAgent(agentId);

      if (response) {
        // Store the single agent in the agents array for display purposes
        setAgents(prev => {
          // Check if we already have this agent to avoid duplicates
          const existingAgent = prev.find(a => a.id === agentId);
          if (existingAgent) return prev;

          return [...prev, response];
        });
      }
      // Agent response was empty/null - agent may have been deleted
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to fetch agent details for ID:', agentId, error);
      }
      // Create placeholder entry for unavailable agent
      setAgents(prev => {
        const existingAgent = prev.find(a => a.id === agentId);
        if (existingAgent) return prev;

        return [...prev, {
          id: agentId,
          name: 'Agent details unavailable',
          status: 'unknown',
          error: 'Failed to load agent details'
        } as any];
      });
    } finally {
      loadingAgentsRef.current = false;
      setLoadingAgents(false);
    }
  }, []);

  // Fetch individual agent details if node has agent_id but agent not in main list
  useEffect(() => {
    const agentId = node.data?.configuration?.agent_id;

    if (node.type === 'ai_agent' && agentId && isAuthenticated && agents.length > 0) {
      const agentExists = agents.find(a => a.id === agentId);

      if (!agentExists && !loadingAgentsRef.current) {
        fetchAgentDetails(agentId);
      }
    }
  }, [node.type, node.data?.configuration?.agent_id, agents, isAuthenticated, fetchAgentDetails]);

  // Update config when node changes (when user selects a different node)
  useEffect(() => {
    // Filter out temporary properties used for forcing re-renders
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { _handleUpdateTimestamp: _temp, ...cleanNodeData } = node.data || {};

    setConfig({
      name: cleanNodeData.name || '',
      description: cleanNodeData.description || '',
      isStartNode: cleanNodeData.isStartNode || false, // Respect existing flags only
      isEndNode: cleanNodeData.isEndNode || false,
      isErrorHandler: cleanNodeData.isErrorHandler || false,
      timeoutSeconds: cleanNodeData.timeoutSeconds || 300,
      retryCount: cleanNodeData.retryCount || 0,
      handlePositions: cleanNodeData.handlePositions ||
        getDefaultHandlePositions(node.type || 'default', cleanNodeData.isStartNode, cleanNodeData.isEndNode),
      configuration: cleanNodeData.configuration || {},
      metadata: cleanNodeData.metadata || {}
    });

    // Reset other states when node changes
    setErrors({});
    setActiveTab('basic');
    setHasChanges(false);

    // Reset agent loading state when switching nodes
    const nodeChanged = currentNodeRef.current !== node.id;
    if (nodeChanged) {
      currentNodeRef.current = node.id;

      if (node.type !== 'ai_agent') {
        agentsLoadedRef.current = false;
        loadingAgentsRef.current = false;
        setAgents([]);
        setLoadingAgents(false);
      } else {
        // Reset loading state to allow fresh agent loading for each AI agent node
        agentsLoadedRef.current = false;
        loadingAgentsRef.current = false;
        setLoadingAgents(false);
      }
    }
  }, [node.id, node.type, node.data]);

  // Simple change tracking - mark changes when user interacts
  const markAsChanged = () => {
    if (!hasChanges) {
      setHasChanges(true);
    }
  };

  // Validation
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

    // AI Agent specific validation
    if (node.type === 'ai_agent') {
      if (!config.configuration?.agent_id) {
        newErrors.agent = 'Agent selection is required';
      }

      // Prompt template is recommended but not strictly required for saving
      // It will be validated at workflow execution time
      // This allows users to save work-in-progress configurations
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  // Handle field changes
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleFieldChange = (field: keyof NodeConfiguration, value: any) => {
    setConfig(prev => ({
      ...prev,
      [field]: value
    }));
    markAsChanged();

    // Clear error when user starts typing
    if (errors[field]) {
      setErrors(prev => {
        const newErrors = { ...prev };
        delete newErrors[field];
        return newErrors;
      });
    }
  };

  // Handle configuration changes
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleConfigChange = (key: string, value: any) => {
    setConfig(prev => ({
      ...prev,
      configuration: {
        ...prev.configuration,
        [key]: value
      }
    }));
    markAsChanged();
  };

  // Handle metadata changes - used by handlePositionChange for non-handlePositions metadata
  // handlePositions is handled specially by handlePositionChange to sync both locations
  const _handleMetadataChange = (key: string, value: unknown) => {
    setConfig(prev => {
      const updatedMetadata = {
        ...prev.metadata,
        [key]: value
      };

      return {
        ...prev,
        metadata: updatedMetadata
      };
    });
    markAsChanged();
  };
  // Suppress unused variable warning - may be needed for future metadata changes
  void _handleMetadataChange;

  // Handle agent selection change
  const handleAgentChange = (agentId: string) => {
    const selectedAgent = agents.find(a => a.id === agentId);
    if (selectedAgent) {
      // Update configuration with new agent
      const updatedConfig = {
        ...config.configuration,
        agent_id: agentId,
        agent_name: selectedAgent.name,
        // Reset or update other agent-specific configurations
        model: selectedAgent.mcp_metadata?.model_config?.model || config.configuration.model,
        provider: selectedAgent.ai_provider?.slug || config.configuration.provider
      };

      setConfig(prev => ({
        ...prev,
        configuration: updatedConfig
      }));
      markAsChanged();
    }
  };

  // Apply changes to node
  const handleSave = () => {
    if (!validateConfig()) {
      return;
    }

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

  // Handle delete
  const handleDelete = () => {
    if (onDelete && window.confirm(`Are you sure you want to delete the node "${config.name}"?`)) {
      onDelete(node.id);
      onClose();
    }
  };

  // Get node type display info
  const getNodeTypeInfo = (nodeType: string) => {
    const typeMap = {
      trigger: { label: 'Trigger', color: 'text-theme-success', icon: '⚡' },
      ai_agent: { label: 'AI Agent', color: 'text-theme-interactive-primary', icon: '🤖' },
      api_call: { label: 'API Call', color: 'text-theme-info', icon: '🌐' },
      condition: { label: 'Condition', color: 'text-theme-warning', icon: '🔀' },
      transform: { label: 'Transform', color: 'text-teal-600', icon: '🔄' }
    };
    return typeMap[nodeType as keyof typeof typeMap] || { label: nodeType, color: 'text-theme-secondary', icon: '⚙️' };
  };

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

                  {/* Display current node flags as read-only info */}
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

                  {/* Error Handler Configuration - still user configurable */}
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
              {renderNodeSpecificConfig()}
            </TabsContent>

            <TabsContent value="advanced" className="space-y-4 mt-0">
              <Input
                label="Timeout (seconds)"
                type="number"
                value={config.timeoutSeconds}
                onChange={(e) => handleFieldChange('timeoutSeconds', parseInt(e.target.value) || 300)}
                min={1}
                error={errors.timeoutSeconds}
              />

              <Input
                label="Retry Count"
                type="number"
                value={config.retryCount}
                onChange={(e) => handleFieldChange('retryCount', parseInt(e.target.value) || 0)}
                min={0}
                max={5}
                error={errors.retryCount}
              />

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Custom Metadata
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
    </div>
  );

  // Render node-specific configuration options
  function renderNodeSpecificConfig() {
    // Get handle definitions for this node type
    const handleDefs = getHandleIdsForNodeType(
      node.type || 'default',
      node.data?.isStartNode || node.type === 'start',
      node.data?.isEndNode || node.type === 'end'
    );

    // Current handle positions (top-level only, no backward compat)
    const currentPositions: HandlePositions = config.handlePositions ||
      getDefaultHandlePositions(node.type || 'default', node.data?.isStartNode, node.data?.isEndNode);

    // Position options for dropdowns
    const positionOptions = [
      { value: 'top', label: 'Top' },
      { value: 'bottom', label: 'Bottom' },
      { value: 'left', label: 'Left' },
      { value: 'right', label: 'Right' }
    ];

    // Handler for per-handle position changes
    const handlePositionChange = (handleId: string, position: HandlePosition) => {
      const updatedPositions = {
        ...currentPositions,
        [handleId]: position
      };
      setConfig(prev => ({
        ...prev,
        handlePositions: updatedPositions
      }));
      markAsChanged();
    };

    // Common per-handle position configuration for all nodes
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

    switch (node.type) {
      case 'start':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Start Trigger Type"
              value={config.configuration.start_trigger || config.configuration.trigger_type || 'manual'}
              onChange={(value) => {
                handleConfigChange('start_trigger', value);
                handleConfigChange('trigger_type', value);
              }}
              options={[
                { value: 'manual', label: 'Manual Start' },
                { value: 'webhook', label: 'Webhook Trigger' },
                { value: 'schedule', label: 'Scheduled Start' },
                { value: 'api', label: 'API Trigger' }
              ]}
            />

            {(config.configuration.start_trigger === 'webhook' || config.configuration.trigger_type === 'webhook') && (
              <Input
                label="Webhook URL"
                value={config.configuration.webhook_url || ''}
                onChange={(e) => handleConfigChange('webhook_url', e.target.value)}
                placeholder="Auto-generated webhook URL"
                disabled
              />
            )}

            {(config.configuration.start_trigger === 'schedule' || config.configuration.trigger_type === 'schedule') && (
              <Input
                label="Schedule (Cron)"
                value={config.configuration.schedule || ''}
                onChange={(e) => handleConfigChange('schedule', e.target.value)}
                placeholder="0 0 * * * (every day at midnight)"
              />
            )}
          </div>
        );

      case 'end':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="End Trigger Type"
              value={config.configuration.end_trigger || 'success'}
              onChange={(value) => handleConfigChange('end_trigger', value)}
              options={[
                { value: 'success', label: 'Success Completion' },
                { value: 'failure', label: 'Failure Completion' },
                { value: 'error', label: 'Error Termination' }
              ]}
            />

            <Textarea
              label="Success Message"
              value={config.configuration.success_message || ''}
              onChange={(e) => handleConfigChange('success_message', e.target.value)}
              placeholder="Workflow completed successfully"
              rows={2}
            />

            <Textarea
              label="Failure Message"
              value={config.configuration.failure_message || ''}
              onChange={(e) => handleConfigChange('failure_message', e.target.value)}
              placeholder="Workflow failed to complete"
              rows={2}
            />

            <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
              <input
                type="checkbox"
                checked={config.configuration.deployment_approved || false}
                onChange={(e) => handleConfigChange('deployment_approved', e.target.checked)}
                className="mt-0.5 rounded border-theme-border"
              />
              <div className="flex-1">
                <label className="text-sm font-medium text-theme-primary">
                  Deployment Approved
                </label>
                <p className="text-xs text-theme-muted mt-1">
                  Mark this end node as indicating successful deployment completion.
                </p>
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Artifacts (Optional)
              </label>
              <Input
                value={(config.configuration.artifacts || []).join(', ')}
                onChange={(e) => handleConfigChange('artifacts', e.target.value.split(',').map(v => v.trim()).filter(v => v))}
                placeholder="file1.txt, output.json, report.pdf"
              />
              <p className="text-xs text-theme-muted mt-1">
                List of files or outputs generated by this workflow (comma-separated)
              </p>
            </div>
          </div>
        );

      case 'ai_agent':
        // Get agent ID from configuration - standardized as agent_id
        const agentId = config.configuration?.agent_id ||
                       node.data?.configuration?.agent_id;

        const selectedAgent = agents?.find(a => a.id === agentId);

        return (
          <div className="space-y-4">
            {handlePositionsConfig}

            {/* Agent Selection */}
            <div>
              <EnhancedSelect
                label="Agent"
                value={agentId || ''}
                onChange={handleAgentChange}
                options={
                  !agents || !Array.isArray(agents) || agents.length === 0
                    ? []
                    : agents.map(agent => ({
                        value: agent.id,
                        label: agent.name,
                        description: `${agent.agent_type} | Model: ${agent.mcp_metadata?.model_config?.model || 'Unknown'} | Provider: ${agent.ai_provider?.name || 'Unknown'}`
                      }))
                }
                placeholder={
                  !isAuthenticated ? "Login required to load agents" :
                  loadingAgents ? "Loading agents..." :
                  !agents || !Array.isArray(agents) || agents.length === 0 ? "No agents available" :
                  "Select an agent..."
                }
                disabled={loadingAgents || !isAuthenticated}
                error={errors.agent}
              />
              {agentId && selectedAgent && !loadingAgents && (
                <div className="mt-2 p-3 bg-theme-surface border border-theme rounded-lg">
                  <div className="grid grid-cols-2 gap-3 text-xs">
                    <div>
                      <span className="text-theme-muted">Type:</span>
                      <span className="ml-1 text-theme-primary font-medium">
                        {selectedAgent.agent_type?.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}
                      </span>
                    </div>
                    <div>
                      <span className="text-theme-muted">Status:</span>
                      <span className={`ml-1 font-medium ${
                        selectedAgent.status === 'active' ? 'text-theme-success' : 'text-theme-warning'
                      }`}>
                        {selectedAgent.status}
                      </span>
                    </div>
                    <div>
                      <span className="text-theme-muted">Model:</span>
                      <span className="ml-1 text-theme-secondary font-mono">
                        {selectedAgent.mcp_metadata?.model_config?.model || 'Not configured'}
                      </span>
                    </div>
                    <div>
                      <span className="text-theme-muted">Provider:</span>
                      <span className="ml-1 text-theme-secondary">
                        {selectedAgent.ai_provider?.name || 'Not configured'}
                      </span>
                    </div>
                  </div>
                  {selectedAgent.description && (
                    <p className="text-xs text-theme-muted mt-2 pt-2 border-t border-theme">
                      {selectedAgent.description}
                    </p>
                  )}
                </div>
              )}
              {agentId && !selectedAgent && !loadingAgents && (
                <p className="text-xs mt-1 text-theme-warning">
                  ⚠️ Selected agent not found or not accessible
                </p>
              )}
            </div>

            <div>
              <Textarea
                label="Prompt Template"
                value={config.configuration.prompt_template || ''}
                onChange={(e) => handleConfigChange('prompt_template', e.target.value)}
                placeholder="Enter prompt template with {{variables}}...&#10;&#10;Example:&#10;Analyze the following data: {{input}}&#10;Consider the context: {{context}}&#10;Provide detailed insights."
                rows={4}
              />
              {!config.configuration.prompt_template?.trim() && (
                <p className="text-xs text-theme-warning mt-1 flex items-center gap-1">
                  <AlertTriangle className="h-3 w-3" />
                  Prompt template is recommended for execution. You can save without it for now.
                </p>
              )}
              <p className="text-xs text-theme-muted mt-1">
                Use {'{{variableName}}'} to reference input variables. Standard variables: {'{{input}}, {{context}}, {{data}}'}
              </p>
            </div>

            <Input
              label="Temperature"
              type="number"
              value={config.configuration.temperature || 0.7}
              onChange={(e) => handleConfigChange('temperature', parseFloat(e.target.value))}
              min={0}
              max={2}
              step={0.1}
            />

            <Input
              label="Max Tokens"
              type="number"
              value={config.configuration.max_tokens || 1000}
              onChange={(e) => handleConfigChange('max_tokens', parseInt(e.target.value))}
              min={1}
              max={8000}
            />

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Input Variables
              </label>
              <Input
                value={(config.configuration.input_variables || ['input', 'context', 'data']).join(', ')}
                onChange={(e) => handleConfigChange('input_variables', e.target.value.split(',').map(v => v.trim()).filter(v => v))}
                placeholder="input, context, data"
              />
              <p className="text-xs text-theme-muted mt-1">
                Standard: input (main), context (metadata), data (structured)
              </p>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Output Variables
              </label>
              <Input
                value={(config.configuration.output_variables || ['output', 'result', 'data']).join(', ')}
                onChange={(e) => handleConfigChange('output_variables', e.target.value.split(',').map(v => v.trim()).filter(v => v))}
                placeholder="output, result, data"
              />
              <p className="text-xs text-theme-muted mt-1">
                Standard: output (main), result (processed), data (passthrough)
              </p>
            </div>
          </div>
        );

      case 'api_call':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="HTTP Method"
              value={config.configuration.method || 'GET'}
              onChange={(value) => handleConfigChange('method', value)}
              options={[
                { value: 'GET', label: 'GET' },
                { value: 'POST', label: 'POST' },
                { value: 'PUT', label: 'PUT' },
                { value: 'DELETE', label: 'DELETE' },
                { value: 'PATCH', label: 'PATCH' }
              ]}
            />

            <Input
              label="URL"
              value={config.configuration.url || ''}
              onChange={(e) => handleConfigChange('url', e.target.value)}
              placeholder="https://api.example.com/endpoint"
            />

            <Textarea
              label="Headers (JSON)"
              value={JSON.stringify(config.configuration.headers || { 'Content-Type': 'application/json' }, null, 2)}
              onChange={(e) => {
                try {
                  const headers = JSON.parse(e.target.value);
                  handleConfigChange('headers', headers);
                } catch {
                  // Invalid JSON
                }
              }}
              rows={3}
              className="font-mono text-sm"
            />

            {config.configuration.method !== 'GET' && (
              <Textarea
                label="Request Body (JSON with variables)"
                value={JSON.stringify(config.configuration.body || { input: '{{input}}', data: '{{data}}' }, null, 2)}
                onChange={(e) => {
                  try {
                    const body = JSON.parse(e.target.value);
                    handleConfigChange('body', body);
                  } catch {
                    // Invalid JSON
                  }
                }}
                rows={4}
                className="font-mono text-sm"
                placeholder='{"input": "{{input}}", "data": "{{data}}"}'
              />
            )}

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Response Mapping
              </label>
              <Textarea
                value={JSON.stringify(config.configuration.response_mapping || { output: 'body', result: 'body.result', data: 'body.data' }, null, 2)}
                onChange={(e) => {
                  try {
                    const mapping = JSON.parse(e.target.value);
                    handleConfigChange('response_mapping', mapping);
                  } catch {
                    // Invalid JSON
                  }
                }}
                rows={3}
                className="font-mono text-sm"
              />
              <p className="text-xs text-theme-muted mt-1">
                Maps API response to standard output variables
              </p>
            </div>
          </div>
        );

      case 'condition':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Condition Type"
              value={config.configuration.conditionType || 'equals'}
              onChange={(value) => handleConfigChange('conditionType', value)}
              options={[
                { value: 'equals', label: 'Equals' },
                { value: 'not_equals', label: 'Not Equals' },
                { value: 'greater_than', label: 'Greater Than' },
                { value: 'less_than', label: 'Less Than' },
                { value: 'contains', label: 'Contains' },
                { value: 'regex', label: 'Regex Match' }
              ]}
            />

            <Input
              label="Variable Path"
              value={config.configuration.variablePath || ''}
              onChange={(e) => handleConfigChange('variablePath', e.target.value)}
              placeholder="data.result.status"
            />

            <Input
              label="Expected Value"
              value={config.configuration.expectedValue || ''}
              onChange={(e) => handleConfigChange('expectedValue', e.target.value)}
              placeholder="success"
            />
          </div>
        );

      case 'transform':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Transform Type"
              value={config.configuration.transformType || 'javascript'}
              onChange={(value) => handleConfigChange('transformType', value)}
              options={[
                { value: 'javascript', label: 'JavaScript' },
                { value: 'jq', label: 'JQ Query' },
                { value: 'template', label: 'Template' }
              ]}
            />

            <Textarea
              label="Transform Code"
              value={config.configuration.code || ''}
              onChange={(e) => handleConfigChange('code', e.target.value)}
              placeholder="// Transform input data\nreturn { result: input.data };"
              rows={8}
              className="font-mono text-sm"
            />
          </div>
        );

      case 'kb_article_create':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <Input
              label="Article Title"
              value={config.configuration.title || ''}
              onChange={(e) => handleConfigChange('title', e.target.value)}
              placeholder="Enter article title or use {{variable}}"
              required
            />

            <Textarea
              label="Content"
              value={config.configuration.content || ''}
              onChange={(e) => handleConfigChange('content', e.target.value)}
              placeholder="Article content supports {{variables}} for dynamic content"
              rows={6}
              required
            />

            <Textarea
              label="Excerpt"
              value={config.configuration.excerpt || ''}
              onChange={(e) => handleConfigChange('excerpt', e.target.value)}
              placeholder="Brief summary of the article"
              rows={2}
            />

            <Input
              label="Category ID"
              value={config.configuration.category_id || ''}
              onChange={(e) => handleConfigChange('category_id', e.target.value)}
              placeholder="Knowledge base category ID"
              required
            />

            <EnhancedSelect
              label="Status"
              value={config.configuration.status || 'draft'}
              onChange={(value) => handleConfigChange('status', value)}
              options={[
                { value: 'draft', label: 'Draft' },
                { value: 'review', label: 'In Review' },
                { value: 'published', label: 'Published' },
                { value: 'archived', label: 'Archived' }
              ]}
            />

            <Input
              label="Tags"
              value={Array.isArray(config.configuration.tags) ? config.configuration.tags.join(', ') : (config.configuration.tags || '')}
              onChange={(e) => handleConfigChange('tags', e.target.value)}
              placeholder="tag1, tag2, tag3 (comma-separated)"
            />

            <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
              <input
                type="checkbox"
                checked={config.configuration.is_public || false}
                onChange={(e) => handleConfigChange('is_public', e.target.checked)}
                className="mt-0.5 rounded border-theme-border"
              />
              <div className="flex-1">
                <label className="text-sm font-medium text-theme-primary">Public Article</label>
                <p className="text-xs text-theme-muted mt-1">Make article visible to all users</p>
              </div>
            </div>

            <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
              <input
                type="checkbox"
                checked={config.configuration.is_featured || false}
                onChange={(e) => handleConfigChange('is_featured', e.target.checked)}
                className="mt-0.5 rounded border-theme-border"
              />
              <div className="flex-1">
                <label className="text-sm font-medium text-theme-primary">Featured Article</label>
                <p className="text-xs text-theme-muted mt-1">Display article in featured section</p>
              </div>
            </div>

            <Input
              label="Output Variable (Optional)"
              value={config.configuration.output_variable || ''}
              onChange={(e) => handleConfigChange('output_variable', e.target.value)}
              placeholder="article_id"
            />
          </div>
        );

      case 'kb_article_read':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-3">Article Identifier</h4>
              <p className="text-xs text-theme-muted mb-3">Provide either Article ID or Slug</p>

              <div className="space-y-3">
                <Input
                  label="Article ID"
                  value={config.configuration.article_id || ''}
                  onChange={(e) => handleConfigChange('article_id', e.target.value)}
                  placeholder="UUID or {{variable}}"
                />

                <Input
                  label="Article Slug"
                  value={config.configuration.article_slug || ''}
                  onChange={(e) => handleConfigChange('article_slug', e.target.value)}
                  placeholder="article-slug or {{variable}}"
                />
              </div>
            </div>

            <Input
              label="Output Variable (Optional)"
              value={config.configuration.output_variable || ''}
              onChange={(e) => handleConfigChange('output_variable', e.target.value)}
              placeholder="article_data"
            />
          </div>
        );

      case 'kb_article_update':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-3">Article Identifier</h4>
              <div className="space-y-3">
                <Input
                  label="Article ID"
                  value={config.configuration.article_id || ''}
                  onChange={(e) => handleConfigChange('article_id', e.target.value)}
                  placeholder="UUID or {{variable}}"
                />

                <Input
                  label="Article Slug"
                  value={config.configuration.article_slug || ''}
                  onChange={(e) => handleConfigChange('article_slug', e.target.value)}
                  placeholder="article-slug or {{variable}}"
                />
              </div>
            </div>

            <h4 className="text-sm font-medium text-theme-primary mb-2">Fields to Update</h4>

            <div className="space-y-3">
              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_title || false}
                  onChange={(e) => handleConfigChange('update_title', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Title</label>
                  {config.configuration.update_title && (
                    <Input
                      value={config.configuration.title || ''}
                      onChange={(e) => handleConfigChange('title', e.target.value)}
                      placeholder="New title or {{variable}}"
                      className="mt-2"
                    />
                  )}
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_content || false}
                  onChange={(e) => handleConfigChange('update_content', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Content</label>
                  {config.configuration.update_content && (
                    <Textarea
                      value={config.configuration.content || ''}
                      onChange={(e) => handleConfigChange('content', e.target.value)}
                      placeholder="New content or {{variable}}"
                      rows={4}
                      className="mt-2"
                    />
                  )}
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_status || false}
                  onChange={(e) => handleConfigChange('update_status', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Status</label>
                  {config.configuration.update_status && (
                    <EnhancedSelect
                      value={config.configuration.status || 'draft'}
                      onChange={(value) => handleConfigChange('status', value)}
                      options={[
                        { value: 'draft', label: 'Draft' },
                        { value: 'review', label: 'In Review' },
                        { value: 'published', label: 'Published' },
                        { value: 'archived', label: 'Archived' }
                      ]}
                      className="mt-2"
                    />
                  )}
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_tags || false}
                  onChange={(e) => handleConfigChange('update_tags', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Tags</label>
                  {config.configuration.update_tags && (
                    <Input
                      value={Array.isArray(config.configuration.tags) ? config.configuration.tags.join(', ') : (config.configuration.tags || '')}
                      onChange={(e) => handleConfigChange('tags', e.target.value)}
                      placeholder="tag1, tag2, tag3"
                      className="mt-2"
                    />
                  )}
                </div>
              </div>
            </div>
          </div>
        );

      case 'kb_article_search':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <Input
              label="Search Query"
              value={config.configuration.query || ''}
              onChange={(e) => handleConfigChange('query', e.target.value)}
              placeholder="Full-text search query or {{variable}}"
            />

            <h4 className="text-sm font-medium text-theme-primary mb-2">Filters</h4>

            <Input
              label="Category ID"
              value={config.configuration.category_id || ''}
              onChange={(e) => handleConfigChange('category_id', e.target.value)}
              placeholder="Filter by category ID"
            />

            <EnhancedSelect
              label="Status Filter"
              value={config.configuration.status || ''}
              onChange={(value) => handleConfigChange('status', value)}
              options={[
                { value: '', label: 'All Statuses' },
                { value: 'draft', label: 'Draft' },
                { value: 'review', label: 'In Review' },
                { value: 'published', label: 'Published' },
                { value: 'archived', label: 'Archived' }
              ]}
            />

            <Input
              label="Tags"
              value={Array.isArray(config.configuration.tags) ? config.configuration.tags.join(', ') : (config.configuration.tags || '')}
              onChange={(e) => handleConfigChange('tags', e.target.value)}
              placeholder="tag1, tag2 (comma-separated)"
            />

            <div className="grid grid-cols-2 gap-3">
              <Input
                label="Limit"
                type="number"
                value={config.configuration.limit || 10}
                onChange={(e) => handleConfigChange('limit', parseInt(e.target.value) || 10)}
                min={1}
                max={100}
              />

              <Input
                label="Offset"
                type="number"
                value={config.configuration.offset || 0}
                onChange={(e) => handleConfigChange('offset', parseInt(e.target.value) || 0)}
                min={0}
              />
            </div>

            <EnhancedSelect
              label="Sort By"
              value={config.configuration.sort_by || 'recent'}
              onChange={(value) => handleConfigChange('sort_by', value)}
              options={[
                { value: 'recent', label: 'Most Recent' },
                { value: 'popular', label: 'Most Popular' },
                { value: 'title', label: 'Title (A-Z)' }
              ]}
            />

            <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
              <input
                type="checkbox"
                checked={config.configuration.is_public === true}
                onChange={(e) => handleConfigChange('is_public', e.target.checked ? true : undefined)}
                className="mt-0.5 rounded border-theme-border"
              />
              <div className="flex-1">
                <label className="text-sm font-medium text-theme-primary">Public Only</label>
                <p className="text-xs text-theme-muted mt-1">Show only public articles</p>
              </div>
            </div>

            <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
              <input
                type="checkbox"
                checked={config.configuration.is_featured === true}
                onChange={(e) => handleConfigChange('is_featured', e.target.checked ? true : undefined)}
                className="mt-0.5 rounded border-theme-border"
              />
              <div className="flex-1">
                <label className="text-sm font-medium text-theme-primary">Featured Only</label>
                <p className="text-xs text-theme-muted mt-1">Show only featured articles</p>
              </div>
            </div>

            <Input
              label="Output Variable (Optional)"
              value={config.configuration.output_variable || ''}
              onChange={(e) => handleConfigChange('output_variable', e.target.value)}
              placeholder="search_results"
            />
          </div>
        );

      case 'kb_article_publish':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-3">Article Identifier</h4>
              <div className="space-y-3">
                <Input
                  label="Article ID"
                  value={config.configuration.article_id || ''}
                  onChange={(e) => handleConfigChange('article_id', e.target.value)}
                  placeholder="UUID or {{variable}}"
                />

                <Input
                  label="Article Slug"
                  value={config.configuration.article_slug || ''}
                  onChange={(e) => handleConfigChange('article_slug', e.target.value)}
                  placeholder="article-slug or {{variable}}"
                />
              </div>
            </div>

            <h4 className="text-sm font-medium text-theme-primary mb-2">Publishing Options</h4>

            <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
              <input
                type="checkbox"
                checked={config.configuration.make_public || false}
                onChange={(e) => handleConfigChange('make_public', e.target.checked)}
                className="mt-0.5 rounded border-theme-border"
              />
              <div className="flex-1">
                <label className="text-sm font-medium text-theme-primary">Make Public</label>
                <p className="text-xs text-theme-muted mt-1">Make article visible to all users</p>
              </div>
            </div>

            <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
              <input
                type="checkbox"
                checked={config.configuration.make_featured || false}
                onChange={(e) => handleConfigChange('make_featured', e.target.checked)}
                className="mt-0.5 rounded border-theme-border"
              />
              <div className="flex-1">
                <label className="text-sm font-medium text-theme-primary">Make Featured</label>
                <p className="text-xs text-theme-muted mt-1">Display article in featured section</p>
              </div>
            </div>
          </div>
        );

      case 'page_create':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <Input
              label="Page Title"
              value={config.configuration.title || ''}
              onChange={(e) => handleConfigChange('title', e.target.value)}
              placeholder="Enter page title or use {{variable}}"
              required
            />

            <Textarea
              label="Content"
              value={config.configuration.content || ''}
              onChange={(e) => handleConfigChange('content', e.target.value)}
              placeholder="Page content supports {{variables}} for dynamic content"
              rows={6}
              required
            />

            <Input
              label="Slug (Optional)"
              value={config.configuration.slug || ''}
              onChange={(e) => handleConfigChange('slug', e.target.value)}
              placeholder="page-slug (auto-generated if empty)"
            />

            <EnhancedSelect
              label="Status"
              value={config.configuration.status || 'draft'}
              onChange={(value) => handleConfigChange('status', value)}
              options={[
                { value: 'draft', label: 'Draft' },
                { value: 'published', label: 'Published' }
              ]}
            />

            <h4 className="text-sm font-medium text-theme-primary mb-2">SEO Metadata</h4>

            <Textarea
              label="Meta Description"
              value={config.configuration.meta_description || ''}
              onChange={(e) => handleConfigChange('meta_description', e.target.value)}
              placeholder="SEO meta description"
              rows={2}
            />

            <Input
              label="Meta Keywords"
              value={config.configuration.meta_keywords || ''}
              onChange={(e) => handleConfigChange('meta_keywords', e.target.value)}
              placeholder="keyword1, keyword2, keyword3"
            />

            <Input
              label="Output Variable (Optional)"
              value={config.configuration.output_variable || ''}
              onChange={(e) => handleConfigChange('output_variable', e.target.value)}
              placeholder="page_id"
            />
          </div>
        );

      case 'page_read':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-3">Page Identifier</h4>
              <p className="text-xs text-theme-muted mb-3">Provide either Page ID or Slug</p>

              <div className="space-y-3">
                <Input
                  label="Page ID"
                  value={config.configuration.page_id || ''}
                  onChange={(e) => handleConfigChange('page_id', e.target.value)}
                  placeholder="UUID or {{variable}}"
                />

                <Input
                  label="Page Slug"
                  value={config.configuration.page_slug || ''}
                  onChange={(e) => handleConfigChange('page_slug', e.target.value)}
                  placeholder="page-slug or {{variable}}"
                />
              </div>
            </div>

            <Input
              label="Output Variable (Optional)"
              value={config.configuration.output_variable || ''}
              onChange={(e) => handleConfigChange('output_variable', e.target.value)}
              placeholder="page_data"
            />
          </div>
        );

      case 'page_update':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-3">Page Identifier</h4>
              <div className="space-y-3">
                <Input
                  label="Page ID"
                  value={config.configuration.page_id || ''}
                  onChange={(e) => handleConfigChange('page_id', e.target.value)}
                  placeholder="UUID or {{variable}}"
                />

                <Input
                  label="Page Slug"
                  value={config.configuration.page_slug || ''}
                  onChange={(e) => handleConfigChange('page_slug', e.target.value)}
                  placeholder="page-slug or {{variable}}"
                />
              </div>
            </div>

            <h4 className="text-sm font-medium text-theme-primary mb-2">Fields to Update</h4>

            <div className="space-y-3">
              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_title || false}
                  onChange={(e) => handleConfigChange('update_title', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Title</label>
                  {config.configuration.update_title && (
                    <Input
                      value={config.configuration.title || ''}
                      onChange={(e) => handleConfigChange('title', e.target.value)}
                      placeholder="New title or {{variable}}"
                      className="mt-2"
                    />
                  )}
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_content || false}
                  onChange={(e) => handleConfigChange('update_content', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Content</label>
                  {config.configuration.update_content && (
                    <Textarea
                      value={config.configuration.content || ''}
                      onChange={(e) => handleConfigChange('content', e.target.value)}
                      placeholder="New content or {{variable}}"
                      rows={4}
                      className="mt-2"
                    />
                  )}
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_slug || false}
                  onChange={(e) => handleConfigChange('update_slug', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Slug</label>
                  {config.configuration.update_slug && (
                    <Input
                      value={config.configuration.slug || ''}
                      onChange={(e) => handleConfigChange('slug', e.target.value)}
                      placeholder="new-page-slug"
                      className="mt-2"
                    />
                  )}
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_status || false}
                  onChange={(e) => handleConfigChange('update_status', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Status</label>
                  {config.configuration.update_status && (
                    <EnhancedSelect
                      value={config.configuration.status || 'draft'}
                      onChange={(value) => handleConfigChange('status', value)}
                      options={[
                        { value: 'draft', label: 'Draft' },
                        { value: 'published', label: 'Published' }
                      ]}
                      className="mt-2"
                    />
                  )}
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_meta_description || false}
                  onChange={(e) => handleConfigChange('update_meta_description', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Meta Description</label>
                  {config.configuration.update_meta_description && (
                    <Textarea
                      value={config.configuration.meta_description || ''}
                      onChange={(e) => handleConfigChange('meta_description', e.target.value)}
                      placeholder="SEO meta description"
                      rows={2}
                      className="mt-2"
                    />
                  )}
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
                <input
                  type="checkbox"
                  checked={config.configuration.update_meta_keywords || false}
                  onChange={(e) => handleConfigChange('update_meta_keywords', e.target.checked)}
                  className="mt-0.5 rounded border-theme-border"
                />
                <div className="flex-1">
                  <label className="text-sm font-medium text-theme-primary">Update Meta Keywords</label>
                  {config.configuration.update_meta_keywords && (
                    <Input
                      value={config.configuration.meta_keywords || ''}
                      onChange={(e) => handleConfigChange('meta_keywords', e.target.value)}
                      placeholder="keyword1, keyword2, keyword3"
                      className="mt-2"
                    />
                  )}
                </div>
              </div>
            </div>
          </div>
        );

      case 'page_publish':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-3">Page Identifier</h4>
              <p className="text-xs text-theme-muted mb-3">Provide either Page ID or Slug</p>

              <div className="space-y-3">
                <Input
                  label="Page ID"
                  value={config.configuration.page_id || ''}
                  onChange={(e) => handleConfigChange('page_id', e.target.value)}
                  placeholder="UUID or {{variable}}"
                />

                <Input
                  label="Page Slug"
                  value={config.configuration.page_slug || ''}
                  onChange={(e) => handleConfigChange('page_slug', e.target.value)}
                  placeholder="page-slug or {{variable}}"
                />
              </div>
            </div>

            <p className="text-xs text-theme-muted p-3 bg-theme-background rounded-lg border border-theme">
              This node will change the page status to 'published' and make it publicly accessible.
            </p>
          </div>
        );

      // MCP (Model Context Protocol) Nodes
      case 'mcp_tool':
        return (
          <McpToolConfigPanel
            configuration={config.configuration}
            onConfigChange={handleConfigChange}
            errors={errors}
            disabled={false}
          />
        );

      case 'mcp_resource':
        return (
          <McpResourceConfigPanel
            configuration={config.configuration}
            onConfigChange={handleConfigChange}
            errors={errors}
            disabled={false}
          />
        );

      case 'mcp_prompt':
        return (
          <McpPromptConfigPanel
            configuration={config.configuration}
            onConfigChange={handleConfigChange}
            errors={errors}
            disabled={false}
          />
        );

      // Unified KB Article Node - dispatches based on action
      case 'kb_article': {
        const kbAction = config.configuration.action || 'create';
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Action"
              value={kbAction}
              onChange={(value) => handleConfigChange('action', value)}
              options={[
                { value: 'create', label: 'Create Article' },
                { value: 'read', label: 'Read Article' },
                { value: 'update', label: 'Update Article' },
                { value: 'search', label: 'Search Articles' },
                { value: 'publish', label: 'Publish Article' }
              ]}
            />
            {/* Action-specific fields rendered inline */}
            {kbAction === 'create' && (
              <>
                <Input
                  label="Article Title"
                  value={config.configuration.title || ''}
                  onChange={(e) => handleConfigChange('title', e.target.value)}
                  placeholder="Enter article title or use {{variable}}"
                />
                <Textarea
                  label="Content"
                  value={config.configuration.content || ''}
                  onChange={(e) => handleConfigChange('content', e.target.value)}
                  placeholder="Article content supports {{variables}}"
                  rows={6}
                />
                <Input
                  label="Category ID"
                  value={config.configuration.category_id || ''}
                  onChange={(e) => handleConfigChange('category_id', e.target.value)}
                  placeholder="Knowledge base category ID"
                />
              </>
            )}
            {kbAction === 'read' && (
              <Input
                label="Article ID"
                value={config.configuration.article_id || ''}
                onChange={(e) => handleConfigChange('article_id', e.target.value)}
                placeholder="Article ID or {{variable}}"
              />
            )}
            {kbAction === 'update' && (
              <>
                <Input
                  label="Article ID"
                  value={config.configuration.article_id || ''}
                  onChange={(e) => handleConfigChange('article_id', e.target.value)}
                  placeholder="Article ID to update"
                />
                <Input
                  label="Title"
                  value={config.configuration.title || ''}
                  onChange={(e) => handleConfigChange('title', e.target.value)}
                  placeholder="New title (optional)"
                />
                <Textarea
                  label="Content"
                  value={config.configuration.content || ''}
                  onChange={(e) => handleConfigChange('content', e.target.value)}
                  placeholder="New content (optional)"
                  rows={6}
                />
              </>
            )}
            {kbAction === 'search' && (
              <>
                <Input
                  label="Search Query"
                  value={config.configuration.query || ''}
                  onChange={(e) => handleConfigChange('query', e.target.value)}
                  placeholder="Search query or {{variable}}"
                />
                <Input
                  label="Category ID (optional)"
                  value={config.configuration.category_id || ''}
                  onChange={(e) => handleConfigChange('category_id', e.target.value)}
                  placeholder="Filter by category"
                />
                <Input
                  label="Max Results"
                  type="number"
                  value={config.configuration.limit || 10}
                  onChange={(e) => handleConfigChange('limit', parseInt(e.target.value) || 10)}
                />
              </>
            )}
            {kbAction === 'publish' && (
              <Input
                label="Article ID"
                value={config.configuration.article_id || ''}
                onChange={(e) => handleConfigChange('article_id', e.target.value)}
                placeholder="Article ID to publish"
              />
            )}
          </div>
        );
      }

      // Unified Page Node - dispatches based on action
      case 'page': {
        const pageAction = config.configuration.action || 'create';
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Action"
              value={pageAction}
              onChange={(value) => handleConfigChange('action', value)}
              options={[
                { value: 'create', label: 'Create Page' },
                { value: 'read', label: 'Read Page' },
                { value: 'update', label: 'Update Page' },
                { value: 'publish', label: 'Publish Page' }
              ]}
            />
            {pageAction === 'create' && (
              <>
                <Input
                  label="Page Title"
                  value={config.configuration.title || ''}
                  onChange={(e) => handleConfigChange('title', e.target.value)}
                  placeholder="Enter page title or use {{variable}}"
                />
                <Textarea
                  label="Content"
                  value={config.configuration.content || ''}
                  onChange={(e) => handleConfigChange('content', e.target.value)}
                  placeholder="Page content supports {{variables}}"
                  rows={6}
                />
                <Input
                  label="Slug"
                  value={config.configuration.slug || ''}
                  onChange={(e) => handleConfigChange('slug', e.target.value)}
                  placeholder="URL slug (auto-generated if empty)"
                />
              </>
            )}
            {pageAction === 'read' && (
              <Input
                label="Page ID or Slug"
                value={config.configuration.page_id || ''}
                onChange={(e) => handleConfigChange('page_id', e.target.value)}
                placeholder="Page ID/slug or {{variable}}"
              />
            )}
            {pageAction === 'update' && (
              <>
                <Input
                  label="Page ID"
                  value={config.configuration.page_id || ''}
                  onChange={(e) => handleConfigChange('page_id', e.target.value)}
                  placeholder="Page ID to update"
                />
                <Input
                  label="Title"
                  value={config.configuration.title || ''}
                  onChange={(e) => handleConfigChange('title', e.target.value)}
                  placeholder="New title (optional)"
                />
                <Textarea
                  label="Content"
                  value={config.configuration.content || ''}
                  onChange={(e) => handleConfigChange('content', e.target.value)}
                  placeholder="New content (optional)"
                  rows={6}
                />
              </>
            )}
            {pageAction === 'publish' && (
              <Input
                label="Page ID"
                value={config.configuration.page_id || ''}
                onChange={(e) => handleConfigChange('page_id', e.target.value)}
                placeholder="Page ID to publish"
              />
            )}
          </div>
        );
      }

      // Unified MCP Operation Node - dispatches based on operation_type
      case 'mcp_operation': {
        const mcpOpType = config.configuration.operation_type || 'tool';
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Operation Type"
              value={mcpOpType}
              onChange={(value) => handleConfigChange('operation_type', value)}
              options={[
                { value: 'tool', label: 'Tool Call' },
                { value: 'resource', label: 'Resource Access' },
                { value: 'prompt', label: 'Prompt Template' }
              ]}
            />
            {mcpOpType === 'tool' && (
              <McpToolConfigPanel
                configuration={config.configuration}
                onConfigChange={handleConfigChange}
                errors={errors}
                disabled={false}
              />
            )}
            {mcpOpType === 'resource' && (
              <McpResourceConfigPanel
                configuration={config.configuration}
                onConfigChange={handleConfigChange}
                errors={errors}
                disabled={false}
              />
            )}
            {mcpOpType === 'prompt' && (
              <McpPromptConfigPanel
                configuration={config.configuration}
                onConfigChange={handleConfigChange}
                errors={errors}
                disabled={false}
              />
            )}
          </div>
        );
      }

      // Loop Node
      case 'loop':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Loop Type"
              value={config.configuration.loop_type || 'for_each'}
              onChange={(value) => handleConfigChange('loop_type', value)}
              options={[
                { value: 'for_each', label: 'For Each Item' },
                { value: 'while', label: 'While Condition' },
                { value: 'count', label: 'Fixed Count' }
              ]}
            />
            {config.configuration.loop_type === 'for_each' && (
              <Input
                label="Collection Variable"
                value={config.configuration.collection || ''}
                onChange={(e) => handleConfigChange('collection', e.target.value)}
                placeholder="{{items}} or variable path"
              />
            )}
            {config.configuration.loop_type === 'while' && (
              <Input
                label="Condition Expression"
                value={config.configuration.condition || ''}
                onChange={(e) => handleConfigChange('condition', e.target.value)}
                placeholder="{{counter}} < 10"
              />
            )}
            {config.configuration.loop_type === 'count' && (
              <Input
                label="Iteration Count"
                type="number"
                value={config.configuration.count || 10}
                onChange={(e) => handleConfigChange('count', parseInt(e.target.value) || 10)}
              />
            )}
            <Input
              label="Max Iterations"
              type="number"
              value={config.configuration.max_iterations || 100}
              onChange={(e) => handleConfigChange('max_iterations', parseInt(e.target.value) || 100)}
            />
          </div>
        );

      // Merge Node
      case 'merge':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Merge Strategy"
              value={config.configuration.merge_strategy || 'wait_all'}
              onChange={(value) => handleConfigChange('merge_strategy', value)}
              options={[
                { value: 'wait_all', label: 'Wait for All Inputs' },
                { value: 'wait_any', label: 'Continue on First Input' },
                { value: 'wait_n', label: 'Wait for N Inputs' }
              ]}
            />
            {config.configuration.merge_strategy === 'wait_n' && (
              <Input
                label="Required Input Count"
                type="number"
                value={config.configuration.required_count || 2}
                onChange={(e) => handleConfigChange('required_count', parseInt(e.target.value) || 2)}
              />
            )}
            <Input
              label="Timeout (seconds)"
              type="number"
              value={config.configuration.timeout || 300}
              onChange={(e) => handleConfigChange('timeout', parseInt(e.target.value) || 300)}
            />
          </div>
        );

      // Split Node
      case 'split':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Split Type"
              value={config.configuration.split_type || 'parallel'}
              onChange={(value) => handleConfigChange('split_type', value)}
              options={[
                { value: 'parallel', label: 'Parallel Execution' },
                { value: 'sequential', label: 'Sequential Execution' },
                { value: 'conditional', label: 'Conditional Routing' },
                { value: 'batch', label: 'Batch Processing' }
              ]}
            />
            {config.configuration.split_type === 'batch' && (
              <Input
                label="Batch Size"
                type="number"
                value={config.configuration.batch_size || 10}
                onChange={(e) => handleConfigChange('batch_size', parseInt(e.target.value) || 10)}
              />
            )}
            <Input
              label="Output Count"
              type="number"
              value={config.configuration.output_count || 2}
              onChange={(e) => handleConfigChange('output_count', parseInt(e.target.value) || 2)}
            />
          </div>
        );

      // Trigger Node
      case 'trigger':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Trigger Type"
              value={config.configuration.trigger_type || 'manual'}
              onChange={(value) => handleConfigChange('trigger_type', value)}
              options={[
                { value: 'manual', label: 'Manual Trigger' },
                { value: 'webhook', label: 'Webhook' },
                { value: 'schedule', label: 'Schedule' },
                { value: 'event', label: 'Event-Based' }
              ]}
            />
            {config.configuration.trigger_type === 'schedule' && (
              <Input
                label="Cron Expression"
                value={config.configuration.cron || ''}
                onChange={(e) => handleConfigChange('cron', e.target.value)}
                placeholder="0 0 * * * (daily at midnight)"
              />
            )}
            {config.configuration.trigger_type === 'event' && (
              <Input
                label="Event Name"
                value={config.configuration.event_name || ''}
                onChange={(e) => handleConfigChange('event_name', e.target.value)}
                placeholder="user.created, order.completed"
              />
            )}
          </div>
        );

      // Human Approval Node
      case 'human_approval':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <Input
              label="Approval Title"
              value={config.configuration.title || ''}
              onChange={(e) => handleConfigChange('title', e.target.value)}
              placeholder="Approval required for..."
            />
            <Textarea
              label="Description"
              value={config.configuration.approval_description || ''}
              onChange={(e) => handleConfigChange('approval_description', e.target.value)}
              placeholder="Please review and approve the following..."
              rows={3}
            />
            <Input
              label="Approver Email/Role"
              value={config.configuration.approver || ''}
              onChange={(e) => handleConfigChange('approver', e.target.value)}
              placeholder="admin@example.com or role:manager"
            />
            <Input
              label="Timeout (hours)"
              type="number"
              value={config.configuration.timeout_hours || 24}
              onChange={(e) => handleConfigChange('timeout_hours', parseInt(e.target.value) || 24)}
            />
          </div>
        );

      // Sub-Workflow Node
      case 'sub_workflow':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <Input
              label="Workflow ID"
              value={config.configuration.workflow_id || ''}
              onChange={(e) => handleConfigChange('workflow_id', e.target.value)}
              placeholder="UUID of the workflow to execute"
            />
            <Input
              label="Workflow Name (display)"
              value={config.configuration.workflow_name || ''}
              onChange={(e) => handleConfigChange('workflow_name', e.target.value)}
              placeholder="Human-readable workflow name"
            />
            <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
              <input
                type="checkbox"
                checked={config.configuration.wait_for_completion !== false}
                onChange={(e) => handleConfigChange('wait_for_completion', e.target.checked)}
                className="mt-0.5 rounded border-theme-border"
              />
              <div className="flex-1">
                <label className="text-sm font-medium text-theme-primary">Wait for Completion</label>
                <p className="text-xs text-theme-muted mt-1">Block until sub-workflow finishes</p>
              </div>
            </div>
          </div>
        );

      // Webhook Node
      case 'webhook':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="HTTP Method"
              value={config.configuration.method || 'POST'}
              onChange={(value) => handleConfigChange('method', value)}
              options={[
                { value: 'GET', label: 'GET' },
                { value: 'POST', label: 'POST' },
                { value: 'PUT', label: 'PUT' },
                { value: 'PATCH', label: 'PATCH' },
                { value: 'DELETE', label: 'DELETE' }
              ]}
            />
            <Input
              label="URL"
              value={config.configuration.url || ''}
              onChange={(e) => handleConfigChange('url', e.target.value)}
              placeholder="https://api.example.com/webhook"
            />
            <Textarea
              label="Headers (JSON)"
              value={config.configuration.headers ? JSON.stringify(config.configuration.headers, null, 2) : ''}
              onChange={(e) => {
                try {
                  handleConfigChange('headers', JSON.parse(e.target.value));
                } catch {
                  // Invalid JSON, store as string temporarily
                }
              }}
              placeholder='{"Authorization": "Bearer {{token}}"}'
              rows={3}
            />
          </div>
        );

      // Database Node
      case 'database':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Operation"
              value={config.configuration.operation || 'query'}
              onChange={(value) => handleConfigChange('operation', value)}
              options={[
                { value: 'query', label: 'Query (SELECT)' },
                { value: 'insert', label: 'Insert' },
                { value: 'update', label: 'Update' },
                { value: 'delete', label: 'Delete' }
              ]}
            />
            <Input
              label="Table/Collection"
              value={config.configuration.table || ''}
              onChange={(e) => handleConfigChange('table', e.target.value)}
              placeholder="users, orders, etc."
            />
            <Textarea
              label="Query/Filter"
              value={config.configuration.query || ''}
              onChange={(e) => handleConfigChange('query', e.target.value)}
              placeholder="SQL query or JSON filter"
              rows={4}
            />
          </div>
        );

      // Email Node
      case 'email':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <Input
              label="To"
              value={config.configuration.to || ''}
              onChange={(e) => handleConfigChange('to', e.target.value)}
              placeholder="recipient@example.com or {{user.email}}"
            />
            <Input
              label="Subject"
              value={config.configuration.subject || ''}
              onChange={(e) => handleConfigChange('subject', e.target.value)}
              placeholder="Email subject with {{variables}}"
            />
            <Textarea
              label="Body"
              value={config.configuration.body || ''}
              onChange={(e) => handleConfigChange('body', e.target.value)}
              placeholder="Email content with {{variables}}"
              rows={6}
            />
            <EnhancedSelect
              label="Content Type"
              value={config.configuration.content_type || 'html'}
              onChange={(value) => handleConfigChange('content_type', value)}
              options={[
                { value: 'html', label: 'HTML' },
                { value: 'text', label: 'Plain Text' }
              ]}
            />
          </div>
        );

      // File Node
      case 'file':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Operation"
              value={config.configuration.operation || 'read'}
              onChange={(value) => handleConfigChange('operation', value)}
              options={[
                { value: 'read', label: 'Read File' },
                { value: 'write', label: 'Write File' },
                { value: 'append', label: 'Append to File' },
                { value: 'delete', label: 'Delete File' }
              ]}
            />
            <Input
              label="File Path"
              value={config.configuration.path || ''}
              onChange={(e) => handleConfigChange('path', e.target.value)}
              placeholder="/path/to/file.txt or {{variable}}"
            />
            {(config.configuration.operation === 'write' || config.configuration.operation === 'append') && (
              <Textarea
                label="Content"
                value={config.configuration.content || ''}
                onChange={(e) => handleConfigChange('content', e.target.value)}
                placeholder="File content to write"
                rows={4}
              />
            )}
          </div>
        );

      // Validator Node
      case 'validator':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Validation Type"
              value={config.configuration.validation_type || 'json-schema'}
              onChange={(value) => handleConfigChange('validation_type', value)}
              options={[
                { value: 'json-schema', label: 'JSON Schema' },
                { value: 'regex', label: 'Regular Expression' },
                { value: 'custom', label: 'Custom Expression' }
              ]}
            />
            <Textarea
              label="Schema/Pattern"
              value={config.configuration.schema || ''}
              onChange={(e) => handleConfigChange('schema', e.target.value)}
              placeholder="JSON schema or regex pattern"
              rows={6}
            />
            <EnhancedSelect
              label="On Failure"
              value={config.configuration.on_failure || 'error'}
              onChange={(value) => handleConfigChange('on_failure', value)}
              options={[
                { value: 'error', label: 'Throw Error' },
                { value: 'skip', label: 'Skip to Next' },
                { value: 'default', label: 'Use Default Value' }
              ]}
            />
          </div>
        );

      // Prompt Template Node
      case 'prompt_template':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <Input
              label="Template Name"
              value={config.configuration.template_name || ''}
              onChange={(e) => handleConfigChange('template_name', e.target.value)}
              placeholder="Name for this template"
            />
            <Textarea
              label="Prompt Template"
              value={config.configuration.template || ''}
              onChange={(e) => handleConfigChange('template', e.target.value)}
              placeholder="You are a {{role}}. Please {{action}} the following: {{input}}"
              rows={8}
            />
            <Input
              label="Output Variable"
              value={config.configuration.output_variable || ''}
              onChange={(e) => handleConfigChange('output_variable', e.target.value)}
              placeholder="Variable name for the result"
            />
          </div>
        );

      // Data Processor Node
      case 'data_processor':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Processing Type"
              value={config.configuration.processing_type || 'map'}
              onChange={(value) => handleConfigChange('processing_type', value)}
              options={[
                { value: 'map', label: 'Map (Transform Each)' },
                { value: 'filter', label: 'Filter' },
                { value: 'reduce', label: 'Reduce/Aggregate' },
                { value: 'sort', label: 'Sort' },
                { value: 'group', label: 'Group By' }
              ]}
            />
            <Textarea
              label="Expression"
              value={config.configuration.expression || ''}
              onChange={(e) => handleConfigChange('expression', e.target.value)}
              placeholder="item.value * 2, item.status === 'active'"
              rows={4}
            />
            <Input
              label="Input Variable"
              value={config.configuration.input_variable || ''}
              onChange={(e) => handleConfigChange('input_variable', e.target.value)}
              placeholder="{{items}} or data path"
            />
          </div>
        );

      // Notification Node
      case 'notification':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Channel"
              value={config.configuration.channel || 'email'}
              onChange={(value) => handleConfigChange('channel', value)}
              options={[
                { value: 'email', label: 'Email' },
                { value: 'slack', label: 'Slack' },
                { value: 'webhook', label: 'Webhook' },
                { value: 'sms', label: 'SMS' }
              ]}
            />
            <Input
              label="Recipient"
              value={config.configuration.recipient || ''}
              onChange={(e) => handleConfigChange('recipient', e.target.value)}
              placeholder="Email, Slack channel, or phone number"
            />
            <Input
              label="Title/Subject"
              value={config.configuration.title || ''}
              onChange={(e) => handleConfigChange('title', e.target.value)}
              placeholder="Notification title"
            />
            <Textarea
              label="Message"
              value={config.configuration.message || ''}
              onChange={(e) => handleConfigChange('message', e.target.value)}
              placeholder="Notification message with {{variables}}"
              rows={4}
            />
          </div>
        );

      // Scheduler Node
      case 'scheduler':
        return (
          <div className="space-y-4">
            {handlePositionsConfig}
            <EnhancedSelect
              label="Schedule Type"
              value={config.configuration.schedule_type || 'delay'}
              onChange={(value) => handleConfigChange('schedule_type', value)}
              options={[
                { value: 'delay', label: 'Delay Execution' },
                { value: 'at_time', label: 'Execute at Specific Time' },
                { value: 'cron', label: 'Cron Schedule' }
              ]}
            />
            {config.configuration.schedule_type === 'delay' && (
              <>
                <Input
                  label="Delay Duration"
                  type="number"
                  value={config.configuration.delay_value || 5}
                  onChange={(e) => handleConfigChange('delay_value', parseInt(e.target.value) || 5)}
                />
                <EnhancedSelect
                  label="Unit"
                  value={config.configuration.delay_unit || 'minutes'}
                  onChange={(value) => handleConfigChange('delay_unit', value)}
                  options={[
                    { value: 'seconds', label: 'Seconds' },
                    { value: 'minutes', label: 'Minutes' },
                    { value: 'hours', label: 'Hours' },
                    { value: 'days', label: 'Days' }
                  ]}
                />
              </>
            )}
            {config.configuration.schedule_type === 'at_time' && (
              <Input
                label="Execute At (ISO DateTime)"
                value={config.configuration.execute_at || ''}
                onChange={(e) => handleConfigChange('execute_at', e.target.value)}
                placeholder="2024-01-01T09:00:00Z or {{variable}}"
              />
            )}
            {config.configuration.schedule_type === 'cron' && (
              <Input
                label="Cron Expression"
                value={config.configuration.cron || ''}
                onChange={(e) => handleConfigChange('cron', e.target.value)}
                placeholder="0 9 * * 1-5 (9am weekdays)"
              />
            )}
          </div>
        );

      default:
        return (
          <div>
            {handlePositionsConfig}
            <div className="text-center py-8 text-theme-muted">
              <Settings className="h-8 w-8 mx-auto mb-2 opacity-50" />
              <p>No specific configuration available for this node type.</p>
              <p className="text-xs mt-2">Connection orientation can be configured above.</p>
            </div>
          </div>
        );
    }
  }
};