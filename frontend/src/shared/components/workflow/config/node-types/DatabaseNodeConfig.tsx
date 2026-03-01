import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const DatabaseNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Operation"
        value={config.configuration.operation || 'query'}
        onChange={(value) => handleConfigChange('operation', value)}
        options={[
          { value: 'query', label: 'Query (SELECT)' },
          { value: 'insert', label: 'Insert' },
          { value: 'update', label: 'Update' },
          { value: 'delete', label: 'Delete' }
        ]}
      />
      <Input
        label="Table/Collection"
        value={config.configuration.table || ''}
        onChange={(e) => handleConfigChange('table', e.target.value)}
        placeholder="users, orders, etc."
      />
      <Textarea
        label="Query/Filter"
        value={config.configuration.query || ''}
        onChange={(e) => handleConfigChange('query', e.target.value)}
        placeholder="SQL query or JSON filter"
        rows={4}
      />
    </div>
  );
};
