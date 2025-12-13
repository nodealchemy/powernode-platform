import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const LoopNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Loop Type"
        value={config.configuration.loop_type || 'for_each'}
        onChange={(value) => handleConfigChange('loop_type', value)}
        options={[
          { value: 'for_each', label: 'For Each Item' },
          { value: 'while', label: 'While Condition' },
          { value: 'count', label: 'Fixed Count' }
        ]}
      />
      {config.configuration.loop_type === 'for_each' && (
        <Input
          label="Collection Variable"
          value={config.configuration.collection || ''}
          onChange={(e) => handleConfigChange('collection', e.target.value)}
          placeholder="{{items}} or variable path"
        />
      )}
      {config.configuration.loop_type === 'while' && (
        <Input
          label="Condition Expression"
          value={config.configuration.condition || ''}
          onChange={(e) => handleConfigChange('condition', e.target.value)}
          placeholder="{{counter}} < 10"
        />
      )}
      {config.configuration.loop_type === 'count' && (
        <Input
          label="Iteration Count"
          type="number"
          value={config.configuration.count || 10}
          onChange={(e) => handleConfigChange('count', parseInt(e.target.value) || 10)}
        />
      )}
      <Input
        label="Max Iterations"
        type="number"
        value={config.configuration.max_iterations || 100}
        onChange={(e) => handleConfigChange('max_iterations', parseInt(e.target.value) || 100)}
      />
    </div>
  );
};
