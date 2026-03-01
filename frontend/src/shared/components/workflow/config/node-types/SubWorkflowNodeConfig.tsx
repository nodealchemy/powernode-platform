import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const SubWorkflowNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const executionMode = config.configuration.execution_mode || 'sync';
  const showTimeout = executionMode === 'sync';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <Input
        label="Workflow ID"
        value={config.configuration.workflow_id || ''}
        onChange={(e) => handleConfigChange('workflow_id', e.target.value)}
        placeholder="UUID of the workflow to execute"
        description="The ID of the sub-workflow to invoke"
        required
      />

      <Input
        label="Workflow Name"
        value={config.configuration.workflow_name || ''}
        onChange={(e) => handleConfigChange('workflow_name', e.target.value)}
        placeholder="Name for reference"
        description="Display name (optional, for documentation)"
      />

      <EnhancedSelect
        label="Execution Mode"
        value={executionMode}
        onChange={(value) => handleConfigChange('execution_mode', value)}
        options={[
          { value: 'sync', label: 'Synchronous (wait for completion)' },
          { value: 'async', label: 'Asynchronous (continue, get result later)' },
          { value: 'fire_and_forget', label: 'Fire and Forget (no result tracking)' }
        ]}
      />

      {showTimeout && (
        <Input
          label="Timeout (seconds)"
          type="number"
          value={config.configuration.timeout_seconds || 300}
          onChange={(e) => handleConfigChange('timeout_seconds', parseInt(e.target.value) || 300)}
          min={1}
          max={3600}
          description="Max time to wait for sub-workflow completion"
        />
      )}

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Inherit Context"
          description="Pass parent workflow context to sub-workflow"
          checked={config.configuration.inherit_context !== false}
          onCheckedChange={(checked) => handleConfigChange('inherit_context', checked)}
        />

        <Checkbox
          label="Propagate Errors"
          description="Fail parent workflow if sub-workflow fails"
          checked={config.configuration.propagate_errors !== false}
          onCheckedChange={(checked) => handleConfigChange('propagate_errors', checked)}
        />
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Input Mapping</p>
        <Textarea
          label="Map Variables to Sub-Workflow (JSON)"
          value={
            typeof config.configuration.input_mapping === 'object'
              ? JSON.stringify(config.configuration.input_mapping, null, 2)
              : config.configuration.input_mapping || ''
          }
          onChange={(e) => {
            try {
              const parsed = JSON.parse(e.target.value);
              handleConfigChange('input_mapping', parsed);
            } catch (_error) {
              handleConfigChange('input_mapping', e.target.value);
            }
          }}
          placeholder={'{\n  "user_id": "{{start.input.user_id}}",\n  "data": "{{previous_node.output}}",\n  "config": "{{workflow.settings}}"\n}'}
          rows={4}
          description="Map parent workflow variables to sub-workflow inputs"
        />
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Output Mapping</p>
        <Textarea
          label="Map Sub-Workflow Outputs (JSON)"
          value={
            typeof config.configuration.output_mapping === 'object'
              ? JSON.stringify(config.configuration.output_mapping, null, 2)
              : config.configuration.output_mapping || ''
          }
          onChange={(e) => {
            try {
              const parsed = JSON.parse(e.target.value);
              handleConfigChange('output_mapping', parsed);
            } catch (_error) {
              handleConfigChange('output_mapping', e.target.value);
            }
          }}
          placeholder={'{\n  "result": "sub_workflow.final_output",\n  "status": "sub_workflow.status",\n  "metrics": "sub_workflow.execution_metrics"\n}'}
          rows={4}
          description="Map sub-workflow outputs back to parent workflow"
        />
      </div>

      {executionMode === 'async' && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
          <p className="text-sm font-medium text-theme-primary mb-3">Async Options</p>

          <div className="space-y-3">
            <Input
              label="Callback Variable"
              value={config.configuration.callback_variable || 'sub_workflow_id'}
              onChange={(e) => handleConfigChange('callback_variable', e.target.value)}
              placeholder="sub_workflow_id"
              description="Variable to store sub-workflow execution ID"
            />

            <Checkbox
              label="Poll for Completion"
              description="Periodically check sub-workflow status"
              checked={config.configuration.poll_completion === true}
              onCheckedChange={(checked) => handleConfigChange('poll_completion', checked)}
            />

            {config.configuration.poll_completion && (
              <Input
                label="Poll Interval (seconds)"
                type="number"
                value={config.configuration.poll_interval || 10}
                onChange={(e) => handleConfigChange('poll_interval', parseInt(e.target.value) || 10)}
                min={5}
                max={300}
                description="How often to check status"
              />
            )}
          </div>
        </div>
      )}

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">result</code> - Sub-workflow final output</li>
          <li><code className="text-theme-accent">status</code> - Execution status (completed/failed)</li>
          <li><code className="text-theme-accent">execution_id</code> - Sub-workflow execution ID</li>
          <li><code className="text-theme-accent">duration_ms</code> - Total execution time</li>
        </ul>
      </div>

      <div className="p-3 bg-theme-info/10 rounded-lg border border-theme-info/30">
        <p className="text-xs text-theme-info font-medium">Tip</p>
        <p className="text-xs text-theme-muted mt-1">
          Sub-workflows allow you to modularize complex logic. Variables from the parent
          workflow are available in the sub-workflow when &quot;Inherit Context&quot; is enabled.
        </p>
      </div>
    </div>
  );
};
