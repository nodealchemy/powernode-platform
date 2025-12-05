import React, { useState, useEffect, useCallback } from 'react';
import { Play, AlertTriangle, Loader2 } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { Select } from '@/shared/components/ui/Select';
import { Badge } from '@/shared/components/ui/Badge';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { workflowsApi } from '@/shared/services/ai';
import type { AiWorkflow } from '@/shared/types/workflow';

interface BatchExecutionModalProps {
  isOpen: boolean;
  onClose: () => void;
  onExecute: (batchConfig: BatchExecutionConfig) => void;
  preSelectedWorkflows?: string[];
}

export interface BatchExecutionConfig {
  workflow_ids: string[];
  concurrency: number;
  stop_on_error: boolean;
  input_variables?: Record<string, unknown>;
  execution_mode: 'parallel' | 'sequential';
  timeout_seconds?: number;
  metadata?: Record<string, unknown>;
}

interface WorkflowSelectionItem extends AiWorkflow {
  selected: boolean;
  canExecute: boolean;
  validationError?: string;
}

export const BatchExecutionModal: React.FC<BatchExecutionModalProps> = ({
  isOpen,
  onClose,
  onExecute,
  preSelectedWorkflows = []
}) => {
  const [workflows, setWorkflows] = useState<WorkflowSelectionItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [executing, setExecuting] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterStatus, setFilterStatus] = useState<'all' | 'published' | 'draft'>('published');

  // Batch configuration
  const [concurrency, setConcurrency] = useState(5);
  const [executionMode, setExecutionMode] = useState<'parallel' | 'sequential'>('parallel');
  const [stopOnError, setStopOnError] = useState(true);
  const [timeoutSeconds, setTimeoutSeconds] = useState<number>(3600); // 1 hour default
  const [sharedInputVariables, setSharedInputVariables] = useState<string>('{}');

  const { addNotification } = useNotifications();

  const loadWorkflows = useCallback(async () => {
    try {
      setLoading(true);
      const response = await workflowsApi.getWorkflows({
        status: filterStatus === 'all' ? undefined : filterStatus,
        page: 1,
        per_page: 100
      });

      const workflowItems: WorkflowSelectionItem[] = response.items.map((workflow: AiWorkflow) => ({
        ...workflow,
        selected: preSelectedWorkflows.includes(workflow.id),
        canExecute: workflow.status === 'active',
        validationError: workflow.status !== 'active' ? 'Workflow must be active to execute' : undefined
      }));

      setWorkflows(workflowItems);
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
  }, [filterStatus, preSelectedWorkflows, addNotification]);

  useEffect(() => {
    if (isOpen) {
      loadWorkflows();
    }
  }, [isOpen, loadWorkflows]);

  const toggleWorkflowSelection = useCallback((workflowId: string) => {
    setWorkflows(prev =>
      prev.map(w =>
        w.id === workflowId
          ? { ...w, selected: !w.selected }
          : w
      )
    );
  }, []);

  const selectAll = useCallback(() => {
    setWorkflows(prev =>
      prev.map(w => ({ ...w, selected: w.canExecute }))
    );
  }, []);

  const deselectAll = useCallback(() => {
    setWorkflows(prev =>
      prev.map(w => ({ ...w, selected: false }))
    );
  }, []);

  const handleExecute = useCallback(async () => {
    const selectedWorkflows = workflows.filter(w => w.selected);

    if (selectedWorkflows.length === 0) {
      addNotification({
        type: 'warning',
        title: 'No Workflows Selected',
        message: 'Please select at least one workflow to execute.'
      });
      return;
    }

    // Validate shared input variables JSON
    let parsedInputVariables: Record<string, unknown> = {};
    try {
      parsedInputVariables = JSON.parse(sharedInputVariables);
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Invalid JSON',
        message: 'Shared input variables must be valid JSON.'
      });
      return;
    }

    const batchConfig: BatchExecutionConfig = {
      workflow_ids: selectedWorkflows.map(w => w.id),
      concurrency: executionMode === 'parallel' ? concurrency : 1,
      stop_on_error: stopOnError,
      input_variables: parsedInputVariables,
      execution_mode: executionMode,
      timeout_seconds: timeoutSeconds,
      metadata: {
        initiated_at: new Date().toISOString(),
        workflow_count: selectedWorkflows.length
      }
    };

    try {
      setExecuting(true);
      onExecute(batchConfig);
      onClose();
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Batch execution error:', error);
      }
      addNotification({
        type: 'error',
        title: 'Execution Error',
        message: 'Failed to start batch execution. Please try again.'
      });
    } finally {
      setExecuting(false);
    }
  }, [workflows, concurrency, executionMode, stopOnError, timeoutSeconds, sharedInputVariables, onExecute, onClose, addNotification]);

  const filteredWorkflows = workflows.filter(w =>
    w.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    w.description?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const selectedCount = workflows.filter(w => w.selected).length;
  const estimatedDuration = selectedCount > 0
    ? executionMode === 'parallel'
      ? Math.ceil(selectedCount / concurrency) * 30 // Estimate 30s per batch
      : selectedCount * 30 // Sequential: 30s each
    : 0;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Batch Workflow Execution"
      size="xl"
    >
      <div className="space-y-6">
        {/* Info Banner */}
        <div className="bg-theme-info bg-opacity-10 border border-theme-info rounded-lg p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-theme-info flex-shrink-0 mt-0.5" />
            <div className="text-sm text-theme-primary">
              <p className="font-medium mb-1">Batch Execution</p>
              <p className="text-theme-secondary">
                Execute multiple workflows in parallel or sequential mode. Configure concurrency limits
                and shared input variables for consistent execution across all workflows.
              </p>
            </div>
          </div>
        </div>

        {/* Configuration Section */}
        <div className="space-y-4">
          <h3 className="text-sm font-semibold text-theme-primary">Execution Configuration</h3>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Execution Mode
              </label>
              <Select
                value={executionMode}
                onChange={(value) => setExecutionMode(value as 'parallel' | 'sequential')}
              >
                <option value="parallel">Parallel</option>
                <option value="sequential">Sequential</option>
              </Select>
              <p className="text-xs text-theme-tertiary mt-1">
                {executionMode === 'parallel'
                  ? 'Execute workflows concurrently for faster completion'
                  : 'Execute workflows one after another in sequence'}
              </p>
            </div>

            {executionMode === 'parallel' && (
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Concurrency Limit
                </label>
                <Input
                  type="number"
                  min={1}
                  max={10}
                  value={concurrency}
                  onChange={(e) => setConcurrency(parseInt(e.target.value) || 1)}
                />
                <p className="text-xs text-theme-tertiary mt-1">
                  Maximum {concurrency} workflows running simultaneously
                </p>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Timeout (seconds)
              </label>
              <Input
                type="number"
                min={60}
                max={7200}
                value={timeoutSeconds}
                onChange={(e) => setTimeoutSeconds(parseInt(e.target.value) || 3600)}
              />
              <p className="text-xs text-theme-tertiary mt-1">
                Maximum execution time per workflow
              </p>
            </div>

            <div className="flex items-start pt-6">
              <Checkbox
                id="stop-on-error"
                checked={stopOnError}
                onCheckedChange={(checked) => setStopOnError(checked as boolean)}
              />
              <label htmlFor="stop-on-error" className="ml-2 text-sm text-theme-primary">
                Stop batch on first error
              </label>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Shared Input Variables (JSON)
            </label>
            <textarea
              value={sharedInputVariables}
              onChange={(e) => setSharedInputVariables(e.target.value)}
              placeholder='{"key": "value"}'
              className="w-full px-3 py-2 bg-theme-input border border-theme rounded-lg text-theme-primary font-mono text-sm placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary resize-none"
              rows={3}
            />
            <p className="text-xs text-theme-tertiary mt-1">
              These variables will be passed to all workflows in the batch
            </p>
          </div>
        </div>

        {/* Workflow Selection Section */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold text-theme-primary">
              Select Workflows ({selectedCount} selected)
            </h3>
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={selectAll}
                disabled={loading}
              >
                Select All
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={deselectAll}
                disabled={loading}
              >
                Deselect All
              </Button>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <Input
              type="text"
              placeholder="Search workflows..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
            <Select
              value={filterStatus}
              onChange={(value) => setFilterStatus(value as 'all' | 'published' | 'draft')}
            >
              <option value="all">All Statuses</option>
              <option value="published">Published</option>
              <option value="draft">Draft</option>
            </Select>
          </div>

          {/* Workflow List */}
          <div className="border border-theme rounded-lg max-h-96 overflow-y-auto">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <Loader2 className="h-8 w-8 animate-spin text-theme-interactive-primary" />
              </div>
            ) : filteredWorkflows.length === 0 ? (
              <div className="text-center py-12">
                <p className="text-theme-tertiary">No workflows found</p>
              </div>
            ) : (
              <div className="divide-y divide-theme">
                {filteredWorkflows.map((workflow) => (
                  <div
                    key={workflow.id}
                    className={`p-4 hover:bg-theme-surface transition-colors ${
                      !workflow.canExecute ? 'opacity-50' : ''
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      <Checkbox
                        id={`workflow-${workflow.id}`}
                        checked={workflow.selected}
                        onCheckedChange={() => toggleWorkflowSelection(workflow.id)}
                        disabled={!workflow.canExecute}
                      />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1">
                          <label
                            htmlFor={`workflow-${workflow.id}`}
                            className="font-medium text-theme-primary cursor-pointer"
                          >
                            {workflow.name}
                          </label>
                          <Badge
                            variant={workflow.status === 'active' ? 'success' : 'outline'}
                            size="sm"
                          >
                            {workflow.status}
                          </Badge>
                        </div>
                        {workflow.description && (
                          <p className="text-sm text-theme-secondary mb-2">
                            {workflow.description}
                          </p>
                        )}
                        {workflow.validationError && (
                          <div className="flex items-center gap-1 text-xs text-theme-error">
                            <AlertTriangle className="h-3 w-3" />
                            <span>{workflow.validationError}</span>
                          </div>
                        )}
                        {workflow.canExecute && (
                          <div className="flex items-center gap-4 text-xs text-theme-tertiary">
                            <span>Version: {workflow.version || '1.0.0'}</span>
                            <span>
                              Nodes: {workflow.nodes?.length || 0}
                            </span>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Summary Section */}
        {selectedCount > 0 && (
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="grid grid-cols-3 gap-4 text-center">
              <div>
                <p className="text-2xl font-semibold text-theme-primary">{selectedCount}</p>
                <p className="text-xs text-theme-tertiary">Workflows Selected</p>
              </div>
              <div>
                <p className="text-2xl font-semibold text-theme-primary">
                  ~{Math.ceil(estimatedDuration / 60)}m
                </p>
                <p className="text-xs text-theme-tertiary">Estimated Duration</p>
              </div>
              <div>
                <p className="text-2xl font-semibold text-theme-primary">
                  {executionMode === 'parallel' ? concurrency : 1}
                </p>
                <p className="text-xs text-theme-tertiary">
                  {executionMode === 'parallel' ? 'Concurrent' : 'Sequential'}
                </p>
              </div>
            </div>
          </div>
        )}

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
            disabled={selectedCount === 0 || executing}
            className="flex items-center gap-2"
          >
            {executing ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Starting Batch...
              </>
            ) : (
              <>
                <Play className="h-4 w-4" />
                Execute {selectedCount} Workflow{selectedCount !== 1 ? 's' : ''}
              </>
            )}
          </Button>
        </div>
      </div>
    </Modal>
  );
};
