import React, { useState, useEffect, useCallback } from 'react';
import { Play, Loader2, Zap } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { Badge } from '@/shared/components/ui/Badge';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { workflowsApi } from '@/shared/services/ai';
import type { AiWorkflow } from '@/shared/types/workflow';

interface StreamingExecutionModalProps {
  isOpen: boolean;
  onClose: () => void;
  onExecute: (workflowId: string, inputVariables: Record<string, unknown>) => void;
  preSelectedWorkflow?: string;
}

interface WorkflowVariableConfig {
  default_value?: string;
  type?: 'string' | 'number' | 'boolean' | 'json';
  required?: boolean;
}

interface InputVariable {
  name: string;
  value: string;
  type: 'string' | 'number' | 'boolean' | 'json';
  required: boolean;
}

export const StreamingExecutionModal: React.FC<StreamingExecutionModalProps> = ({
  isOpen,
  onClose,
  onExecute,
  preSelectedWorkflow
}) => {
  const [workflows, setWorkflows] = useState<AiWorkflow[]>([]);
  const [selectedWorkflowId, setSelectedWorkflowId] = useState<string>(preSelectedWorkflow || '');
  const [loading, setLoading] = useState(true);
  const [executing, setExecuting] = useState(false);
  const [inputVariables, setInputVariables] = useState<InputVariable[]>([]);
  const [enableStreaming, setEnableStreaming] = useState(true);
  const [enableRealTimeUpdates, setEnableRealTimeUpdates] = useState(true);

  const { addNotification } = useNotifications();

  const loadWorkflows = useCallback(async () => {
    try {
      setLoading(true);
      const response = await workflowsApi.getWorkflows({
        status: 'published',
        page: 1,
        per_page: 100
      });

      setWorkflows(response.items);

      // If a workflow is pre-selected, load its input variables
      if (preSelectedWorkflow) {
        const workflow = response.items.find((w: AiWorkflow) => w.id === preSelectedWorkflow);
        if (workflow) {
          loadWorkflowVariables(workflow);
        }
      }
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load workflows:', error);
      }
      addNotification({
        type: 'error',
        title: 'Load Error',
        message: 'Failed to load workflows. Please try again.'
      });
    } finally {
      setLoading(false);
    }
  }, [preSelectedWorkflow, addNotification]);

  useEffect(() => {
    if (isOpen) {
      loadWorkflows();
    }
  }, [isOpen, loadWorkflows]);

  const loadWorkflowVariables = (workflow: AiWorkflow) => {
    // Extract input variables from workflow configuration
    const variables: InputVariable[] = [];

    if (workflow.variables) {
      Object.entries(workflow.variables).forEach(([name, configData]) => {
        const config = configData as WorkflowVariableConfig;
        variables.push({
          name,
          value: config.default_value || '',
          type: config.type || 'string',
          required: config.required || false
        });
      });
    }

    setInputVariables(variables);
  };

  const handleWorkflowChange = (workflowId: string) => {
    setSelectedWorkflowId(workflowId);
    const workflow = workflows.find(w => w.id === workflowId);
    if (workflow) {
      loadWorkflowVariables(workflow);
    }
  };

  const handleVariableChange = (index: number, value: string) => {
    setInputVariables(prev => {
      const updated = [...prev];
      updated[index] = { ...updated[index], value };
      return updated;
    });
  };

  const validateInputs = (): boolean => {
    if (!selectedWorkflowId) {
      addNotification({
        type: 'warning',
        title: 'No Workflow Selected',
        message: 'Please select a workflow to execute.'
      });
      return false;
    }

    // Validate required variables
    const missingRequired = inputVariables.filter(v => v.required && !v.value);
    if (missingRequired.length > 0) {
      addNotification({
        type: 'warning',
        title: 'Missing Required Variables',
        message: `Please provide values for: ${missingRequired.map(v => v.name).join(', ')}`
      });
      return false;
    }

    // Validate JSON variables
    const jsonVariables = inputVariables.filter(v => v.type === 'json' && v.value);
    for (const variable of jsonVariables) {
      try {
        JSON.parse(variable.value);
      } catch {
        addNotification({
          type: 'error',
          title: 'Invalid JSON',
          message: `Variable "${variable.name}" must be valid JSON.`
        });
        return false;
      }
    }

    return true;
  };

  const handleExecute = useCallback(async () => {
    if (!validateInputs()) return;

    // Convert input variables to execution format
    const variablesObj: Record<string, unknown> = {};
    inputVariables.forEach(variable => {
      if (!variable.value) return;

      switch (variable.type) {
        case 'number':
          variablesObj[variable.name] = parseFloat(variable.value);
          break;
        case 'boolean':
          variablesObj[variable.name] = variable.value.toLowerCase() === 'true';
          break;
        case 'json':
          try {
            variablesObj[variable.name] = JSON.parse(variable.value);
          } catch {
            variablesObj[variable.name] = variable.value;
          }
          break;
        default:
          variablesObj[variable.name] = variable.value;
      }
    });

    try {
      setExecuting(true);
      onExecute(selectedWorkflowId, variablesObj);
      onClose();
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Streaming execution error:', error);
      }
      addNotification({
        type: 'error',
        title: 'Execution Error',
        message: 'Failed to start streaming execution. Please try again.'
      });
    } finally {
      setExecuting(false);
    }
  }, [selectedWorkflowId, inputVariables, enableStreaming, enableRealTimeUpdates, onExecute, onClose, addNotification, validateInputs]);

  const selectedWorkflow = workflows.find(w => w.id === selectedWorkflowId);

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Start Streaming Execution"
      size="lg"
    >
      <div className="space-y-6">
        {/* Info Banner */}
        <div className="bg-theme-info bg-opacity-10 border border-theme-info rounded-lg p-4">
          <div className="flex items-start gap-3">
            <Zap className="h-5 w-5 text-theme-info flex-shrink-0 mt-0.5" />
            <div className="text-sm text-theme-primary">
              <p className="font-medium mb-1">Real-Time Streaming Execution</p>
              <p className="text-theme-secondary">
                Execute workflow with real-time message streaming. You'll see AI responses,
                tool calls, and execution progress as they happen.
              </p>
            </div>
          </div>
        </div>

        {/* Workflow Selection */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Select Workflow
          </label>
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-theme-interactive-primary" />
            </div>
          ) : (
            <select
              value={selectedWorkflowId}
              onChange={(e) => handleWorkflowChange(e.target.value)}
              className="w-full px-3 py-2 bg-theme-input border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            >
              <option value="">Choose a workflow...</option>
              {workflows.map((workflow) => (
                <option key={workflow.id} value={workflow.id}>
                  {workflow.name} {workflow.version && `(v${workflow.version})`}
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Workflow Details */}
        {selectedWorkflow && (
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <h4 className="font-medium text-theme-primary">{selectedWorkflow.name}</h4>
                <Badge variant="success" size="sm">
                  {selectedWorkflow.status}
                </Badge>
              </div>
              {selectedWorkflow.description && (
                <p className="text-sm text-theme-secondary">{selectedWorkflow.description}</p>
              )}
              <div className="flex items-center gap-4 text-xs text-theme-tertiary">
                <span>Version: {selectedWorkflow.version || '1.0.0'}</span>
                <span>Nodes: {selectedWorkflow.nodes?.length || 0}</span>
              </div>
            </div>
          </div>
        )}

        {/* Input Variables */}
        {inputVariables.length > 0 && (
          <div>
            <h4 className="text-sm font-medium text-theme-primary mb-3">
              Input Variables {inputVariables.filter(v => v.required).length > 0 && (
                <span className="text-theme-tertiary">
                  ({inputVariables.filter(v => v.required).length} required)
                </span>
              )}
            </h4>
            <div className="space-y-3">
              {inputVariables.map((variable, index) => (
                <div key={variable.name}>
                  <label className="block text-sm text-theme-primary mb-1">
                    {variable.name}
                    {variable.required && <span className="text-theme-error ml-1">*</span>}
                    <span className="text-theme-tertiary ml-2 text-xs">({variable.type})</span>
                  </label>
                  {variable.type === 'boolean' ? (
                    <select
                      value={variable.value}
                      onChange={(e) => handleVariableChange(index, e.target.value)}
                      className="w-full px-3 py-2 bg-theme-input border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                    >
                      <option value="">Select value...</option>
                      <option value="true">True</option>
                      <option value="false">False</option>
                    </select>
                  ) : variable.type === 'json' ? (
                    <textarea
                      value={variable.value}
                      onChange={(e) => handleVariableChange(index, e.target.value)}
                      placeholder='{"key": "value"}'
                      className="w-full px-3 py-2 bg-theme-input border border-theme rounded-lg text-theme-primary font-mono text-sm focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary resize-none"
                      rows={3}
                    />
                  ) : (
                    <Input
                      type={variable.type === 'number' ? 'number' : 'text'}
                      value={variable.value}
                      onChange={(e) => handleVariableChange(index, e.target.value)}
                      placeholder={`Enter ${variable.name}...`}
                    />
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Streaming Options */}
        <div className="space-y-3 p-4 bg-theme-surface border border-theme rounded-lg">
          <h4 className="text-sm font-medium text-theme-primary mb-2">Streaming Options</h4>

          <div className="flex items-start">
            <Checkbox
              id="enable-streaming"
              checked={enableStreaming}
              onCheckedChange={(checked) => setEnableStreaming(checked as boolean)}
            />
            <label htmlFor="enable-streaming" className="ml-2 text-sm">
              <span className="text-theme-primary font-medium">Enable Streaming</span>
              <p className="text-theme-tertiary text-xs mt-1">
                Receive AI responses in real-time as they are generated
              </p>
            </label>
          </div>

          <div className="flex items-start">
            <Checkbox
              id="enable-realtime"
              checked={enableRealTimeUpdates}
              onCheckedChange={(checked) => setEnableRealTimeUpdates(checked as boolean)}
            />
            <label htmlFor="enable-realtime" className="ml-2 text-sm">
              <span className="text-theme-primary font-medium">Real-Time Updates</span>
              <p className="text-theme-tertiary text-xs mt-1">
                Show node execution progress and status updates live
              </p>
            </label>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex justify-end gap-3 pt-4 border-t border-theme">
          <Button
            variant="outline"
            onClick={onClose}
            disabled={executing}
          >
            Cancel
          </Button>
          <Button
            onClick={handleExecute}
            disabled={!selectedWorkflowId || executing}
            className="flex items-center gap-2"
          >
            {executing ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Starting...
              </>
            ) : (
              <>
                <Play className="h-4 w-4" />
                Start Streaming
              </>
            )}
          </Button>
        </div>
      </div>
    </Modal>
  );
};
