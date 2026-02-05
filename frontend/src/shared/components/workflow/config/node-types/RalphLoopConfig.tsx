import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

const operationOptions = [
  // Lifecycle operations
  { value: 'create', label: 'Create Loop', group: 'Lifecycle' },
  { value: 'start', label: 'Start Loop', group: 'Lifecycle' },
  { value: 'pause', label: 'Pause Loop', group: 'Lifecycle' },
  { value: 'resume', label: 'Resume Loop', group: 'Lifecycle' },
  { value: 'cancel', label: 'Cancel Loop', group: 'Lifecycle' },
  // Execution operations
  { value: 'run_iteration', label: 'Run Single Iteration', group: 'Execution' },
  { value: 'run_to_completion', label: 'Run to Completion', group: 'Execution' },
  // Information operations
  { value: 'status', label: 'Get Status', group: 'Information' },
  { value: 'get_learnings', label: 'Get Learnings', group: 'Information' },
  // Task management operations
  { value: 'add_task', label: 'Add Task', group: 'Task Management' },
  { value: 'parse_prd', label: 'Parse PRD', group: 'Task Management' }
];

const schedulingModeOptions = [
  { value: 'manual', label: 'Manual' },
  { value: 'auto', label: 'Automatic' },
  { value: 'scheduled', label: 'Scheduled' }
];

export const RalphLoopConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const operation = config.configuration.operation || 'create';
  const isCreateOperation = operation === 'create';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      {/* Operation Selector */}
      <EnhancedSelect
        label="Operation"
        value={operation}
        onChange={(value) => handleConfigChange('operation', value)}
        options={operationOptions}
      />

      {/* Loop Identification (for non-create operations) */}
      {!isCreateOperation && (
        <div className="space-y-3 p-3 bg-theme-background rounded-lg border border-theme">
          <p className="text-xs text-theme-muted font-medium uppercase tracking-wide">Loop Identification</p>
          <Input
            label="Loop ID"
            value={config.configuration.loop_id || ''}
            onChange={(e) => handleConfigChange('loop_id', e.target.value)}
            placeholder="Enter loop ID directly"
          />
          <div className="flex items-center gap-2 text-xs text-theme-muted">
            <span>— or —</span>
          </div>
          <Input
            label="Loop Variable"
            value={config.configuration.loop_variable || ''}
            onChange={(e) => handleConfigChange('loop_variable', e.target.value)}
            placeholder="Variable containing loop ID (e.g., created_loop_id)"
          />
        </div>
      )}

      {/* Create Operation Fields */}
      {operation === 'create' && (
        <>
          <Input
            label="Loop Name"
            value={config.configuration.name || ''}
            onChange={(e) => handleConfigChange('name', e.target.value)}
            placeholder="Enter loop name or use {{variable}}"
          />
          <Textarea
            label="Description"
            value={config.configuration.description || ''}
            onChange={(e) => handleConfigChange('description', e.target.value)}
            placeholder="Describe the loop's purpose"
            rows={3}
          />
          <Input
            label="Default Agent ID"
            value={config.configuration.default_agent_id || ''}
            onChange={(e) => handleConfigChange('default_agent_id', e.target.value)}
            placeholder="Agent ID or {{variable}}"
          />
          <Input
            label="Max Iterations"
            type="number"
            value={config.configuration.max_iterations || 100}
            onChange={(e) => handleConfigChange('max_iterations', parseInt(e.target.value) || 100)}
          />
          <Input
            label="Repository URL"
            value={config.configuration.repository_url || ''}
            onChange={(e) => handleConfigChange('repository_url', e.target.value)}
            placeholder="https://github.com/org/repo"
          />
          <Input
            label="Branch"
            value={config.configuration.branch || ''}
            onChange={(e) => handleConfigChange('branch', e.target.value)}
            placeholder="main"
          />
          <EnhancedSelect
            label="Scheduling Mode"
            value={config.configuration.scheduling_mode || 'manual'}
            onChange={(value) => handleConfigChange('scheduling_mode', value)}
            options={schedulingModeOptions}
          />
          <Textarea
            label="PRD JSON (optional)"
            value={config.configuration.prd_json || ''}
            onChange={(e) => handleConfigChange('prd_json', e.target.value)}
            placeholder='{"requirements": [...], "tasks": [...]}'
            rows={4}
          />
        </>
      )}

      {/* Run to Completion Fields */}
      {operation === 'run_to_completion' && (
        <>
          <Input
            label="Max Iterations Override"
            type="number"
            value={config.configuration.max_iterations || ''}
            onChange={(e) => handleConfigChange('max_iterations', e.target.value ? parseInt(e.target.value) : undefined)}
            placeholder="Leave empty to use loop default"
          />
          <Input
            label="Timeout (seconds)"
            type="number"
            value={config.configuration.timeout_seconds || ''}
            onChange={(e) => handleConfigChange('timeout_seconds', e.target.value ? parseInt(e.target.value) : undefined)}
            placeholder="Maximum execution time"
          />
          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="stop_on_error"
              checked={config.configuration.stop_on_error || false}
              onChange={(e) => handleConfigChange('stop_on_error', e.target.checked)}
              className="w-4 h-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
            />
            <label htmlFor="stop_on_error" className="text-sm text-theme-secondary">
              Stop on Error
            </label>
          </div>
        </>
      )}

      {/* Cancel Fields */}
      {operation === 'cancel' && (
        <Textarea
          label="Cancellation Reason"
          value={config.configuration.reason || ''}
          onChange={(e) => handleConfigChange('reason', e.target.value)}
          placeholder="Reason for cancellation"
          rows={2}
        />
      )}

      {/* Add Task Fields */}
      {operation === 'add_task' && (
        <>
          <Input
            label="Task Key"
            value={config.configuration.task_key || ''}
            onChange={(e) => handleConfigChange('task_key', e.target.value)}
            placeholder="Unique task identifier"
          />
          <Textarea
            label="Task Description"
            value={config.configuration.task_description || ''}
            onChange={(e) => handleConfigChange('task_description', e.target.value)}
            placeholder="Describe what the task should accomplish"
            rows={3}
          />
          <Input
            label="Priority"
            type="number"
            value={config.configuration.priority ?? 1}
            onChange={(e) => handleConfigChange('priority', parseInt(e.target.value) || 1)}
            min={1}
            max={10}
          />
          <Input
            label="Dependencies (comma-separated)"
            value={Array.isArray(config.configuration.dependencies) ? config.configuration.dependencies.join(', ') : ''}
            onChange={(e) => handleConfigChange('dependencies', e.target.value.split(',').map(d => d.trim()).filter(Boolean))}
            placeholder="task-1, task-2"
          />
          <Textarea
            label="Acceptance Criteria"
            value={config.configuration.acceptance_criteria || ''}
            onChange={(e) => handleConfigChange('acceptance_criteria', e.target.value)}
            placeholder="Criteria to verify task completion"
            rows={3}
          />
        </>
      )}

      {/* Parse PRD Fields */}
      {operation === 'parse_prd' && (
        <>
          <Textarea
            label="PRD Data"
            value={config.configuration.prd_data || ''}
            onChange={(e) => handleConfigChange('prd_data', e.target.value)}
            placeholder="PRD content to parse (JSON or text)"
            rows={6}
          />
          <div className="flex items-center gap-2 text-xs text-theme-muted">
            <span>— or —</span>
          </div>
          <Input
            label="PRD Variable"
            value={config.configuration.prd_variable || ''}
            onChange={(e) => handleConfigChange('prd_variable', e.target.value)}
            placeholder="Variable containing PRD data"
          />
        </>
      )}

      {/* Output Variable (for all operations) */}
      <Input
        label="Output Variable"
        value={config.configuration.output_variable || ''}
        onChange={(e) => handleConfigChange('output_variable', e.target.value)}
        placeholder="Store result in variable"
      />
    </div>
  );
};
