import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const WebhookNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="HTTP Method"
        value={config.configuration.method || 'POST'}
        onChange={(value) => handleConfigChange('method', value)}
        options={[
          { value: 'GET', label: 'GET' },
          { value: 'POST', label: 'POST' },
          { value: 'PUT', label: 'PUT' },
          { value: 'PATCH', label: 'PATCH' },
          { value: 'DELETE', label: 'DELETE' }
        ]}
      />
      <Input
        label="URL"
        value={config.configuration.url || ''}
        onChange={(e) => handleConfigChange('url', e.target.value)}
        placeholder="https://api.example.com/webhook"
      />
      <Textarea
        label="Headers (JSON)"
        value={config.configuration.headers ? JSON.stringify(config.configuration.headers, null, 2) : ''}
        onChange={(e) => {
          try {
            handleConfigChange('headers', JSON.parse(e.target.value));
          } catch {
            // Invalid JSON, store as string temporarily
          }
        }}
        placeholder='{"Authorization": "Bearer {{token}}"}'
        rows={3}
      />
    </div>
  );
};
