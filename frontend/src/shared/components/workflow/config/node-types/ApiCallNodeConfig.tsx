import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const ApiCallNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const method = config.configuration.method || 'GET';
  const bodyType = config.configuration.body_type || 'json';
  const showBody = ['POST', 'PUT', 'PATCH'].includes(method);

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <EnhancedSelect
        label="HTTP Method"
        value={method}
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
        placeholder="https://api.example.com/users/{{user_id}}"
        description="Use {{variable}} for path parameters"
      />

      <Textarea
        label="Path Parameters (JSON)"
        value={
          typeof config.configuration.path_parameters === 'object'
            ? JSON.stringify(config.configuration.path_parameters, null, 2)
            : config.configuration.path_parameters || ''
        }
        onChange={(e) => {
          try {
            const parsed = JSON.parse(e.target.value);
            handleConfigChange('path_parameters', parsed);
          } catch (_error) {
            handleConfigChange('path_parameters', e.target.value);
          }
        }}
        placeholder='{"user_id": "{{previous_node.user_id}}"}'
        rows={2}
        description="Variables to substitute in URL path"
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
          } catch (_error) {
            handleConfigChange('headers', e.target.value);
          }
        }}
        placeholder='{"Content-Type": "application/json", "Authorization": "Bearer {{token}}"}'
        rows={3}
      />

      <Textarea
        label="Query Parameters (JSON)"
        value={
          typeof config.configuration.query_params === 'object'
            ? JSON.stringify(config.configuration.query_params, null, 2)
            : config.configuration.query_params || ''
        }
        onChange={(e) => {
          try {
            const parsed = JSON.parse(e.target.value);
            handleConfigChange('query_params', parsed);
          } catch (_error) {
            handleConfigChange('query_params', e.target.value);
          }
        }}
        placeholder='{"page": 1, "limit": 10}'
        rows={2}
        description="URL query string parameters"
      />

      {showBody && (
        <>
          <EnhancedSelect
            label="Body Type"
            value={bodyType}
            onChange={(value) => handleConfigChange('body_type', value)}
            options={[
              { value: 'json', label: 'JSON (application/json)' },
              { value: 'form-data', label: 'Form Data (multipart/form-data)' },
              { value: 'x-www-form-urlencoded', label: 'URL Encoded (x-www-form-urlencoded)' },
              { value: 'raw', label: 'Raw Text' }
            ]}
          />

          <Textarea
            label={bodyType === 'raw' ? 'Request Body' : 'Request Body (JSON)'}
            value={
              typeof config.configuration.body === 'object'
                ? JSON.stringify(config.configuration.body, null, 2)
                : config.configuration.body || ''
            }
            onChange={(e) => {
              if (bodyType === 'raw') {
                handleConfigChange('body', e.target.value);
              } else {
                try {
                  const parsed = JSON.parse(e.target.value);
                  handleConfigChange('body', parsed);
                } catch (_error) {
                  handleConfigChange('body', e.target.value);
                }
              }
            }}
            placeholder={bodyType === 'raw' ? 'Raw body content...' : '{"key": "value"}'}
            rows={4}
          />
        </>
      )}

      <Input
        label="Timeout (seconds)"
        type="number"
        value={config.configuration.timeout || 30}
        onChange={(e) => handleConfigChange('timeout', parseInt(e.target.value) || 30)}
        min={1}
        max={300}
        description="Max time to wait for response"
      />

      <Textarea
        label="Response Mapping (JSONPath)"
        value={config.configuration.response_mapping || ''}
        onChange={(e) => handleConfigChange('response_mapping', e.target.value)}
        placeholder="$.data.items[*].id&#10;$.result.user.name"
        rows={2}
        description="Extract specific data from response using JSONPath"
      />

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Retry Configuration</p>

        <div className="space-y-3">
          <Checkbox
            label="Enable Retries"
            description="Automatically retry failed requests"
            checked={config.configuration.retry_enabled === true}
            onCheckedChange={(checked) => handleConfigChange('retry_enabled', checked)}
          />

          {config.configuration.retry_enabled && (
            <>
              <Input
                label="Retry Count"
                type="number"
                value={config.configuration.retry_count || 3}
                onChange={(e) => handleConfigChange('retry_count', parseInt(e.target.value) || 3)}
                min={1}
                max={5}
                description="Number of retry attempts"
              />

              <Input
                label="Retry Delay (seconds)"
                type="number"
                value={config.configuration.retry_delay || 1}
                onChange={(e) => handleConfigChange('retry_delay', parseInt(e.target.value) || 1)}
                min={1}
                max={60}
                description="Delay between retries"
              />

              <Input
                label="Retry on Status Codes"
                value={config.configuration.retry_on_status || '500,502,503,504'}
                onChange={(e) => handleConfigChange('retry_on_status', e.target.value)}
                placeholder="500,502,503,504"
                description="Comma-separated HTTP status codes to retry on"
              />
            </>
          )}
        </div>
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">response</code> - Full response body</li>
          <li><code className="text-theme-accent">status_code</code> - HTTP status code</li>
          <li><code className="text-theme-accent">headers</code> - Response headers</li>
          <li><code className="text-theme-accent">mapped_data</code> - JSONPath extracted data</li>
        </ul>
      </div>
    </div>
  );
};
