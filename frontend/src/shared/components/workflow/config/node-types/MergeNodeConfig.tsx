import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const MergeNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const strategy = config.configuration.strategy || 'wait_all';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <EnhancedSelect
        label="Merge Strategy"
        value={strategy}
        onChange={(value) => handleConfigChange('strategy', value)}
        options={[
          { value: 'wait_all', label: 'Wait for All Inputs' },
          { value: 'wait_any', label: 'Continue on First Input' },
          { value: 'wait_n', label: 'Wait for N Inputs' },
          { value: 'first_success', label: 'First Successful Result' }
        ]}
      />

      {strategy === 'wait_n' && (
        <Input
          label="Required Input Count"
          type="number"
          value={config.configuration.required_count || 2}
          onChange={(e) => handleConfigChange('required_count', parseInt(e.target.value) || 2)}
          min={1}
          max={10}
          description="Number of inputs required to continue"
        />
      )}

      <Input
        label="Timeout (seconds)"
        type="number"
        value={config.configuration.timeout || 300}
        onChange={(e) => handleConfigChange('timeout', parseInt(e.target.value) || 300)}
        min={1}
        max={3600}
        description="Max time to wait for inputs"
      />

      <Input
        label="Source Node IDs"
        value={config.configuration.source_nodes || ''}
        onChange={(e) => handleConfigChange('source_nodes', e.target.value)}
        placeholder="node_1, node_2, node_3"
        description="Comma-separated list of node IDs to wait for (optional)"
      />

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Output Configuration</p>

        <div className="space-y-3">
          <EnhancedSelect
            label="Output Format"
            value={config.configuration.output_format || 'object'}
            onChange={(value) => handleConfigChange('output_format', value)}
            options={[
              { value: 'object', label: 'Object (keyed by node ID)' },
              { value: 'array', label: 'Array (ordered list)' },
              { value: 'merge', label: 'Merged Object (combined)' },
              { value: 'first', label: 'First Value Only' }
            ]}
          />

          <Checkbox
            label="Include Metadata"
            description="Include execution timestamps and node info"
            checked={config.configuration.include_metadata === true}
            onCheckedChange={(checked) => handleConfigChange('include_metadata', checked)}
          />
        </div>
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Default Values</p>
        <Textarea
          label="Default Value for Missing Inputs (JSON)"
          value={
            typeof config.configuration.default_values === 'object'
              ? JSON.stringify(config.configuration.default_values, null, 2)
              : config.configuration.default_values || ''
          }
          onChange={(e) => {
            try {
              const parsed = JSON.parse(e.target.value);
              handleConfigChange('default_values', parsed);
            } catch {
              handleConfigChange('default_values', e.target.value);
            }
          }}
          placeholder={'{\n  "node_1": null,\n  "node_2": {"status": "skipped"}\n}'}
          rows={3}
          description="Values to use when an input times out or is missing"
        />
      </div>

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Fail on Timeout"
          description="Mark as failed if not all inputs arrive in time"
          checked={config.configuration.fail_on_timeout === true}
          onCheckedChange={(checked) => handleConfigChange('fail_on_timeout', checked)}
        />

        <Checkbox
          label="Preserve Order"
          description="Output results in the order nodes completed"
          checked={config.configuration.preserve_order === true}
          onCheckedChange={(checked) => handleConfigChange('preserve_order', checked)}
        />
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">merged</code> - Combined result from all inputs</li>
          <li><code className="text-theme-accent">inputs_received</code> - Number of inputs received</li>
          <li><code className="text-theme-accent">inputs_expected</code> - Number of inputs expected</li>
          <li><code className="text-theme-accent">completed_nodes</code> - List of node IDs that completed</li>
        </ul>
      </div>

      <div className="p-3 bg-theme-info/10 rounded-lg border border-theme-info/30">
        <p className="text-xs text-theme-info font-medium">Tip</p>
        <p className="text-xs text-theme-muted mt-1">
          Merge nodes synchronize parallel branches. Connect multiple nodes to this
          node&apos;s input to wait for all of them before continuing.
        </p>
      </div>
    </div>
  );
};
