import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const ApiCallNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="HTTP Method"
        value={config.configuration.method || 'GET'}
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
        placeholder="https://api.example.com/endpoint"
      />

      <Textarea
        label="Headers (JSON)"
        value={
          typeof config.configuration.headers === 'object'
            ? JSON.stringify(config.configuration.headers, null, 2)
            : config.configuration.headers || ''
        }
        onChange={(e) => {
          try {
            const parsed = JSON.parse(e.target.value);
            handleConfigChange('headers', parsed);
          } catch {
            handleConfigChange('headers', e.target.value);
          }
        }}
        placeholder='{"Content-Type": "application/json"}'
        rows={3}
      />

      <Textarea
        label="Request Body (JSON)"
        value={
          typeof config.configuration.body === 'object'
            ? JSON.stringify(config.configuration.body, null, 2)
            : config.configuration.body || ''
        }
        onChange={(e) => {
          try {
            const parsed = JSON.parse(e.target.value);
            handleConfigChange('body', parsed);
          } catch {
            handleConfigChange('body', e.target.value);
          }
        }}
        placeholder='{"key": "value"}'
        rows={4}
      />
    </div>
  );
};
