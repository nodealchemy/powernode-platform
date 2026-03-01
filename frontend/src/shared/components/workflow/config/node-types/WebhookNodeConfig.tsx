import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const WebhookNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const authType = config.configuration.auth_type || 'none';
  const showPayload = ['POST', 'PUT', 'PATCH'].includes(config.configuration.method || 'POST');

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
        placeholder="https://api.example.com/webhook/{{endpoint}}"
        description="Webhook endpoint URL"
        required
      />

      <Input
        label="Timeout (seconds)"
        type="number"
        value={config.configuration.timeout || 30}
        onChange={(e) => handleConfigChange('timeout', parseInt(e.target.value) || 30)}
        min={1}
        max={300}
        description="Max time to wait for response"
      />

      {/* Authentication */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Authentication</p>

        <div className="space-y-3">
          <EnhancedSelect
            label="Auth Type"
            value={authType}
            onChange={(value) => handleConfigChange('auth_type', value)}
            options={[
              { value: 'none', label: 'None' },
              { value: 'basic', label: 'Basic Auth' },
              { value: 'bearer', label: 'Bearer Token' },
              { value: 'api_key', label: 'API Key' },
              { value: 'oauth2', label: 'OAuth 2.0' }
            ]}
          />

          {authType === 'basic' && (
            <>
              <Input
                label="Username"
                value={config.configuration.auth_username || ''}
                onChange={(e) => handleConfigChange('auth_username', e.target.value)}
                placeholder="username or {{variable}}"
              />
              <Input
                label="Password"
                type="password"
                value={config.configuration.auth_password || ''}
                onChange={(e) => handleConfigChange('auth_password', e.target.value)}
                placeholder="password or {{secret.password}}"
              />
            </>
          )}

          {authType === 'bearer' && (
            <Input
              label="Token"
              value={config.configuration.auth_token || ''}
              onChange={(e) => handleConfigChange('auth_token', e.target.value)}
              placeholder="{{secrets.api_token}}"
              description="Bearer token for Authorization header"
            />
          )}

          {authType === 'api_key' && (
            <>
              <Input
                label="API Key Name"
                value={config.configuration.api_key_name || 'X-API-Key'}
                onChange={(e) => handleConfigChange('api_key_name', e.target.value)}
                placeholder="X-API-Key"
                description="Header name for API key"
              />
              <Input
                label="API Key Value"
                value={config.configuration.api_key_value || ''}
                onChange={(e) => handleConfigChange('api_key_value', e.target.value)}
                placeholder="{{secrets.api_key}}"
              />
              <EnhancedSelect
                label="Key Location"
                value={config.configuration.api_key_location || 'header'}
                onChange={(value) => handleConfigChange('api_key_location', value)}
                options={[
                  { value: 'header', label: 'Header' },
                  { value: 'query', label: 'Query Parameter' }
                ]}
              />
            </>
          )}

          {authType === 'oauth2' && (
            <>
              <Input
                label="Client ID"
                value={config.configuration.oauth_client_id || ''}
                onChange={(e) => handleConfigChange('oauth_client_id', e.target.value)}
                placeholder="{{secrets.oauth_client_id}}"
              />
              <Input
                label="Client Secret"
                type="password"
                value={config.configuration.oauth_client_secret || ''}
                onChange={(e) => handleConfigChange('oauth_client_secret', e.target.value)}
                placeholder="{{secrets.oauth_client_secret}}"
              />
              <Input
                label="Token URL"
                value={config.configuration.oauth_token_url || ''}
                onChange={(e) => handleConfigChange('oauth_token_url', e.target.value)}
                placeholder="https://auth.example.com/oauth/token"
              />
            </>
          )}
        </div>
      </div>

      {/* Headers */}
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
        placeholder='{"Content-Type": "application/json", "X-Custom-Header": "{{value}}"}'
        rows={3}
        description="Additional HTTP headers"
      />

      {/* Payload */}
      {showPayload && (
        <Textarea
          label="Payload Template"
          value={config.configuration.payload || ''}
          onChange={(e) => handleConfigChange('payload', e.target.value)}
          placeholder={'{\n  "event": "{{event_type}}",\n  "data": {{data | json}},\n  "timestamp": "{{timestamp}}"\n}'}
          rows={5}
          description="Request body with variable interpolation"
        />
      )}

      {/* Retry Configuration */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Retry Configuration</p>

        <div className="space-y-3">
          <Checkbox
            label="Enable Retries"
            description="Retry on failure"
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
                max={10}
              />

              <Input
                label="Retry Delay (seconds)"
                type="number"
                value={config.configuration.retry_delay || 5}
                onChange={(e) => handleConfigChange('retry_delay', parseInt(e.target.value) || 5)}
                min={1}
                max={300}
                description="Initial delay between retries"
              />

              <Checkbox
                label="Exponential Backoff"
                description="Double delay after each retry"
                checked={config.configuration.exponential_backoff === true}
                onCheckedChange={(checked) => handleConfigChange('exponential_backoff', checked)}
              />

              <Input
                label="Retry on Status Codes"
                value={config.configuration.retry_on_status || '500,502,503,504'}
                onChange={(e) => handleConfigChange('retry_on_status', e.target.value)}
                placeholder="500,502,503,504"
                description="Comma-separated status codes to retry on"
              />
            </>
          )}
        </div>
      </div>

      {/* Webhook Signature */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Request Signing</p>

        <div className="space-y-3">
          <Checkbox
            label="Sign Request"
            description="Add HMAC signature to request"
            checked={config.configuration.sign_request === true}
            onCheckedChange={(checked) => handleConfigChange('sign_request', checked)}
          />

          {config.configuration.sign_request && (
            <>
              <Input
                label="Signature Secret"
                type="password"
                value={config.configuration.signature_secret || ''}
                onChange={(e) => handleConfigChange('signature_secret', e.target.value)}
                placeholder="{{secrets.webhook_secret}}"
                description="Secret key for HMAC signature"
              />

              <EnhancedSelect
                label="Signature Algorithm"
                value={config.configuration.signature_algorithm || 'sha256'}
                onChange={(value) => handleConfigChange('signature_algorithm', value)}
                options={[
                  { value: 'sha256', label: 'HMAC-SHA256' },
                  { value: 'sha512', label: 'HMAC-SHA512' },
                  { value: 'sha1', label: 'HMAC-SHA1' }
                ]}
              />

              <Input
                label="Signature Header"
                value={config.configuration.signature_header || 'X-Webhook-Signature'}
                onChange={(e) => handleConfigChange('signature_header', e.target.value)}
                placeholder="X-Webhook-Signature"
              />
            </>
          )}
        </div>
      </div>

      {/* Execution Mode */}
      <div className="space-y-3 pt-2">
        <Checkbox
          label="Async Mode (Fire and Forget)"
          description="Don't wait for response"
          checked={config.configuration.async_mode === true}
          onCheckedChange={(checked) => handleConfigChange('async_mode', checked)}
        />

        <Checkbox
          label="Follow Redirects"
          description="Automatically follow HTTP redirects"
          checked={config.configuration.follow_redirects !== false}
          onCheckedChange={(checked) => handleConfigChange('follow_redirects', checked)}
        />
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">response</code> - Response body</li>
          <li><code className="text-theme-accent">status_code</code> - HTTP status code</li>
          <li><code className="text-theme-accent">headers</code> - Response headers</li>
          <li><code className="text-theme-accent">duration_ms</code> - Request duration</li>
          <li><code className="text-theme-accent">retry_count</code> - Number of retries used</li>
        </ul>
      </div>
    </div>
  );
};
