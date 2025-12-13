import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import type { NodeTypeConfigProps } from './types';

export const SubWorkflowNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
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
        placeholder="Name for reference"
      />
      <Textarea
        label="Input Mapping (JSON)"
        value={
          typeof config.configuration.input_mapping === 'object'
            ? JSON.stringify(config.configuration.input_mapping, null, 2)
            : config.configuration.input_mapping || ''
        }
        onChange={(e) => {
          try {
            const parsed = JSON.parse(e.target.value);
            handleConfigChange('input_mapping', parsed);
          } catch {
            handleConfigChange('input_mapping', e.target.value);
          }
        }}
        placeholder='{"subInput": "{{parentOutput}}"}'
        rows={3}
      />
    </div>
  );
};
