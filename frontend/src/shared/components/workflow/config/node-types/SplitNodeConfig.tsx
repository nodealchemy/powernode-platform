import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const SplitNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const splitType = config.configuration.split_type || 'parallel';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <EnhancedSelect
        label="Split Type"
        value={splitType}
        onChange={(value) => handleConfigChange('split_type', value)}
        options={[
          { value: 'parallel', label: 'Parallel Execution' },
          { value: 'sequential', label: 'Sequential Execution' },
          { value: 'conditional', label: 'Conditional Routing' },
          { value: 'batch', label: 'Batch Processing' },
          { value: 'round_robin', label: 'Round Robin Distribution' }
        ]}
      />

      <Input
        label="Branch Count"
        type="number"
        value={config.configuration.branch_count || 2}
        onChange={(e) => handleConfigChange('branch_count', parseInt(e.target.value) || 2)}
        min={2}
        max={10}
        description="Number of parallel branches to create"
      />

      {splitType === 'parallel' && (
        <Input
          label="Parallel Limit"
          type="number"
          value={config.configuration.parallel_limit || 0}
          onChange={(e) => handleConfigChange('parallel_limit', parseInt(e.target.value) || 0)}
          min={0}
          max={100}
          description="Max concurrent branches (0 = unlimited)"
        />
      )}

      {splitType === 'batch' && (
        <>
          <Input
            label="Batch Size"
            type="number"
            value={config.configuration.batch_size || 10}
            onChange={(e) => handleConfigChange('batch_size', parseInt(e.target.value) || 10)}
            min={1}
            max={1000}
            description="Items per batch"
          />

          <Input
            label="Collection Variable"
            value={config.configuration.collection || ''}
            onChange={(e) => handleConfigChange('collection', e.target.value)}
            placeholder="{{items}} or {{data.records}}"
            description="Array to split into batches"
          />
        </>
      )}

      {splitType === 'conditional' && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
          <p className="text-sm font-medium text-theme-primary mb-3">Branch Conditions</p>
          <Textarea
            label="Conditions (JSON)"
            value={
              typeof config.configuration.conditions === 'object'
                ? JSON.stringify(config.configuration.conditions, null, 2)
                : config.configuration.conditions || ''
            }
            onChange={(e) => {
              try {
                const parsed = JSON.parse(e.target.value);
                handleConfigChange('conditions', parsed);
              } catch (_error) {
                handleConfigChange('conditions', e.target.value);
              }
            }}
            placeholder={'[\n  {"branch": 0, "condition": "{{status}} === \'active\'"},\n  {"branch": 1, "condition": "{{status}} === \'pending\'"},\n  {"branch": 2, "condition": "true"}\n]'}
            rows={5}
            description="Conditions for routing to each branch"
          />

          <Checkbox
            label="Allow Multiple Matches"
            description="Send to all matching branches (not just first)"
            checked={config.configuration.allow_multiple === true}
            onCheckedChange={(checked) => handleConfigChange('allow_multiple', checked)}
          />
        </div>
      )}

      <Input
        label="Timeout (seconds)"
        type="number"
        value={config.configuration.timeout || 300}
        onChange={(e) => handleConfigChange('timeout', parseInt(e.target.value) || 300)}
        min={1}
        max={3600}
        description="Max time for all branches to complete"
      />

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Merge Results"
          description="Collect outputs from all branches into single result"
          checked={config.configuration.merge_results !== false}
          onCheckedChange={(checked) => handleConfigChange('merge_results', checked)}
        />

        <Checkbox
          label="Wait for All"
          description="Wait for all branches before continuing"
          checked={config.configuration.wait_for_all !== false}
          onCheckedChange={(checked) => handleConfigChange('wait_for_all', checked)}
        />

        <Checkbox
          label="Fail on Any Error"
          description="Mark as failed if any branch fails"
          checked={config.configuration.fail_on_any_error === true}
          onCheckedChange={(checked) => handleConfigChange('fail_on_any_error', checked)}
        />
      </div>

      {/* Data Distribution */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Data Distribution</p>

        <EnhancedSelect
          label="Input Distribution"
          value={config.configuration.distribution || 'clone'}
          onChange={(value) => handleConfigChange('distribution', value)}
          options={[
            { value: 'clone', label: 'Clone to All Branches' },
            { value: 'split', label: 'Split Data Across Branches' },
            { value: 'select', label: 'Select Specific Fields per Branch' }
          ]}
        />

        {config.configuration.distribution === 'select' && (
          <Textarea
            label="Field Selection (JSON)"
            value={
              typeof config.configuration.field_selection === 'object'
                ? JSON.stringify(config.configuration.field_selection, null, 2)
                : config.configuration.field_selection || ''
            }
            onChange={(e) => {
              try {
                const parsed = JSON.parse(e.target.value);
                handleConfigChange('field_selection', parsed);
              } catch (_error) {
                handleConfigChange('field_selection', e.target.value);
              }
            }}
            placeholder={'{\n  "branch_0": ["user", "settings"],\n  "branch_1": ["orders", "payments"]\n}'}
            rows={4}
            description="Fields to send to each branch"
          />
        )}
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">branch_results</code> - Array of results from each branch</li>
          <li><code className="text-theme-accent">branch_count</code> - Number of branches executed</li>
          <li><code className="text-theme-accent">completed_count</code> - Number successfully completed</li>
          <li><code className="text-theme-accent">failed_branches</code> - IDs of failed branches</li>
        </ul>
      </div>
    </div>
  );
};
