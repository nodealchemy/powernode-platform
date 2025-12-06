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

// Define the workflow node data structure
export interface WorkflowNodeData {
  name?: string;
  description?: string;
  isStartNode?: boolean;
  isEndNode?: boolean;
  isErrorHandler?: boolean;
  timeoutSeconds?: number;
  retryCount?: number;
  handleOrientation?: 'vertical' | 'horizontal';
  configuration?: Record<string, any>;
  metadata?: Record<string, any>;
  _handleUpdateTimestamp?: number;
  [key: string]: any; // Allow additional properties
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
  configuration: Record<string, any>;
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
  const [config, setConfig] = useState<NodeConfiguration>({
    name: node.data?.name || '',
    description: node.data?.description || '',
    isStartNode: node.data?.isStartNode || false, // Respect existing flags only
    isEndNode: node.data?.isEndNode || false,
    isErrorHandler: node.data?.isErrorHandler || false,
    timeoutSeconds: node.data?.timeoutSeconds || 300,
    retryCount: node.data?.retryCount || 0,
    configuration: node.data?.configuration || {},
    metadata: {
      ...(node.data?.metadata || {}),
      // Sync handleOrientation from node.data if it's set at the top level
      handleOrientation: node.data?.handleOrientation || node.data?.metadata?.handleOrientation || 'vertical'
    }
  });

  const [activeTab, setActiveTab] = useState('basic');
  const [hasChanges, setHasChanges] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});

  // Helper function to extract agent list from various response structures
  const extractAgentList = (response: any): AiAgent[] => {
    // Handle paginated response format (items array)
    if (response?.items && Array.isArray(response.items)) {
      return response.items;
    }
    // Handle nested response structures
    if (response?.data?.data?.agents && Array.isArray(response.data.data.agents)) {
      return response.data.data.agents;
    } else if (response?.data?.agents && Array.isArray(response.data.agents)) {
      return response.data.agents;
    } else if (response?.agents && Array.isArray(response.agents)) {
      return response.agents;
    } else if (Array.isArray(response)) {
      return response;
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
    } catch (error: any) {
      console.error('Failed to load available agents:', error);

      // Set empty array but mark as loaded to prevent infinite retries
      setAgents([]);

      // If authentication error, don't mark as loaded so it can retry when user logs in
      if (error.response?.status !== 401 && error.response?.status !== 403) {
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
      } else {
      }
    } catch (error) {
      console.error('Failed to fetch agent details for ID:', agentId, error);
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
      configuration: cleanNodeData.configuration || {},
      metadata: {
        ...(cleanNodeData.metadata || {}),
        // Sync handleOrientation from node.data if it's set at the top level
        // This ensures auto-arrange updates are reflected in the config panel
        handleOrientation: cleanNodeData.handleOrientation || cleanNodeData.metadata?.handleOrientation || 'vertical'
      }
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

  // Handle metadata changes
  const handleMetadataChange = (key: string, value: any) => {
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

    onUpdate(node.id, {
      name: config.name,
      description: config.description,
      isStartNode: config.isStartNode,
      isEndNode: config.isEndNode,
      isErrorHandler: config.isErrorHandler,
      timeoutSeconds: config.timeoutSeconds,
      retryCount: config.retryCount,
      configuration: config.configuration,
      metadata: config.metadata
    });

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
    // Common orientation configuration for all nodes
    const orientationConfig = (
      <div className="mb-6">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Connection Orientation</h4>
        <EnhancedSelect
          label="Handle Position"
          value={config.metadata?.handleOrientation || node.data?.handleOrientation || 'vertical'}
          onChange={(value) => handleMetadataChange('handleOrientation', value)}
          options={[
            { value: 'vertical', label: 'Vertical (Top/Bottom)' },
            { value: 'horizontal', label: 'Horizontal (Left/Right)' }
          ]}
        />
        <p className="text-xs text-theme-muted mt-2">
          Determines where connection handles appear on the node. Vertical places handles on top and bottom, horizontal places them on left and right sides.
        </p>
      </div>
    );

    switch (node.type) {
      case 'start':
        return (
          <div className="space-y-4">
            {orientationConfig}
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

      case 'trigger':
        return (
          <div className="space-y-4">
            <EnhancedSelect
              label="Trigger Type"
              value={config.configuration.triggerType || 'manual'}
              onChange={(value) => handleConfigChange('triggerType', value)}
              options={[
                { value: 'manual', label: 'Manual Trigger' },
                { value: 'webhook', label: 'Webhook' },
                { value: 'schedule', label: 'Scheduled' },
                { value: 'event', label: 'Event-based' }
              ]}
            />

            {config.configuration.triggerType === 'webhook' && (
              <Input
                label="Webhook URL"
                value={config.configuration.webhookUrl || ''}
                onChange={(e) => handleConfigChange('webhookUrl', e.target.value)}
                placeholder="https://example.com/webhook"
              />
            )}

            {config.configuration.triggerType === 'schedule' && (
              <Input
                label="Cron Expression"
                value={config.configuration.cronExpression || ''}
                onChange={(e) => handleConfigChange('cronExpression', e.target.value)}
                placeholder="0 0 * * *"
              />
            )}
          </div>
        );

      case 'end':
        return (
          <div className="space-y-4">
            {orientationConfig}
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
            {orientationConfig}

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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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
            {orientationConfig}
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

      default:
        return (
          <div>
            {orientationConfig}
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