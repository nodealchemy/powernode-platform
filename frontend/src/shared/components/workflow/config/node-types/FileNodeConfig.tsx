import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const FileNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Operation"
        value={config.configuration.operation || 'read'}
        onChange={(value) => handleConfigChange('operation', value)}
        options={[
          { value: 'read', label: 'Read File' },
          { value: 'write', label: 'Write File' },
          { value: 'append', label: 'Append to File' },
          { value: 'delete', label: 'Delete File' }
        ]}
      />
      <Input
        label="File Path"
        value={config.configuration.path || ''}
        onChange={(e) => handleConfigChange('path', e.target.value)}
        placeholder="/path/to/file.txt or {{variable}}"
      />
      {(config.configuration.operation === 'write' || config.configuration.operation === 'append') && (
        <Textarea
          label="Content"
          value={config.configuration.content || ''}
          onChange={(e) => handleConfigChange('content', e.target.value)}
          placeholder="File content to write"
          rows={4}
        />
      )}
    </div>
  );
};
