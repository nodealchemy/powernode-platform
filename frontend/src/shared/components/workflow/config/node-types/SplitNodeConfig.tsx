import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const SplitNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
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
};
