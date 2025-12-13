import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const ConditionNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <Input
        label="Condition Expression"
        value={config.configuration.condition || ''}
        onChange={(e) => handleConfigChange('condition', e.target.value)}
        placeholder="{{input}} > 10"
      />

      <EnhancedSelect
        label="Operator"
        value={config.configuration.operator || 'equals'}
        onChange={(value) => handleConfigChange('operator', value)}
        options={[
          { value: 'equals', label: 'Equals' },
          { value: 'not_equals', label: 'Not Equals' },
          { value: 'greater_than', label: 'Greater Than' },
          { value: 'less_than', label: 'Less Than' },
          { value: 'contains', label: 'Contains' },
          { value: 'regex', label: 'Regex Match' }
        ]}
      />
    </div>
  );
};
