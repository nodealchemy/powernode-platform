import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const DataProcessorNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Processing Type"
        value={config.configuration.processing_type || 'map'}
        onChange={(value) => handleConfigChange('processing_type', value)}
        options={[
          { value: 'map', label: 'Map (Transform Each)' },
          { value: 'filter', label: 'Filter' },
          { value: 'reduce', label: 'Reduce/Aggregate' },
          { value: 'sort', label: 'Sort' },
          { value: 'group', label: 'Group By' }
        ]}
      />
      <Textarea
        label="Expression"
        value={config.configuration.expression || ''}
        onChange={(e) => handleConfigChange('expression', e.target.value)}
        placeholder="item.value * 2, item.status === 'active'"
        rows={4}
      />
      <Input
        label="Input Variable"
        value={config.configuration.input_variable || ''}
        onChange={(e) => handleConfigChange('input_variable', e.target.value)}
        placeholder="{{items}} or data path"
      />
    </div>
  );
};
