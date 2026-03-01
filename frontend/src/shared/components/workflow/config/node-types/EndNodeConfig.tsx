import React from 'react';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const EndNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
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
        label="Output Mapping"
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
            // If not valid JSON, store as string
            handleConfigChange('output_mapping', e.target.value);
          }
        }}
        placeholder='{"result": "{{previousNode.output}}"}'
        rows={3}
      />
      <p className="text-xs text-theme-muted">
        Define how to map the final workflow output. Use JSON format.
      </p>
    </div>
  );
};
