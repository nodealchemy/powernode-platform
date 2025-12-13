import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const MergeNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Merge Strategy"
        value={config.configuration.merge_strategy || 'wait_all'}
        onChange={(value) => handleConfigChange('merge_strategy', value)}
        options={[
          { value: 'wait_all', label: 'Wait for All Inputs' },
          { value: 'wait_any', label: 'Continue on First Input' },
          { value: 'wait_n', label: 'Wait for N Inputs' }
        ]}
      />
      {config.configuration.merge_strategy === 'wait_n' && (
        <Input
          label="Required Input Count"
          type="number"
          value={config.configuration.required_count || 2}
          onChange={(e) => handleConfigChange('required_count', parseInt(e.target.value) || 2)}
        />
      )}
      <Input
        label="Timeout (seconds)"
        type="number"
        value={config.configuration.timeout || 300}
        onChange={(e) => handleConfigChange('timeout', parseInt(e.target.value) || 300)}
      />
    </div>
  );
};
