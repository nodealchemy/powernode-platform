import React from 'react';
import { Shield, HelpCircle } from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';

export interface OAuthConfig {
  authType: 'none' | 'api_key' | 'oauth2';
  oauthProvider: string;
  oauthClientId: string;
  oauthClientSecret: string;
  oauthAuthorizationUrl: string;
  oauthTokenUrl: string;
  oauthScopes: string;
}

interface OAuthConfigFieldsProps {
  config: OAuthConfig;
  onChange: <K extends keyof OAuthConfig>(field: K, value: OAuthConfig[K]) => void;
  errors: Record<string, string>;
}

export const OAuthConfigFields: React.FC<OAuthConfigFieldsProps> = ({
  config,
  onChange,
  errors,
}) => (
  <div className="border-t border-theme pt-4 space-y-4">
    <div className="flex items-center gap-2">
      <Shield className="h-4 w-4 text-theme-info" />
      <h3 className="text-sm font-medium text-theme-primary">Authentication</h3>
    </div>

    <div>
      <label className="block text-sm font-medium text-theme-primary mb-1">
        Authentication Type
      </label>
      <Select
        value={config.authType}
        onChange={(value) => onChange('authType', value as 'none' | 'api_key' | 'oauth2')}
      >
        <option value="none">None (Public)</option>
        <option value="api_key">API Key</option>
        <option value="oauth2">OAuth 2.1</option>
      </Select>
    </div>

    {config.authType === 'oauth2' && (
      <div className="space-y-4 p-4 bg-theme-hover rounded-lg border border-theme">
        <div className="flex items-center gap-2 text-sm text-theme-secondary">
          <HelpCircle className="h-4 w-4" />
          <span>Configure OAuth 2.1 credentials from your MCP server provider</span>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Provider Name
          </label>
          <Input
            type="text"
            value={config.oauthProvider}
            onChange={(e) => onChange('oauthProvider', e.target.value)}
            placeholder="e.g., GitHub, Google, Slack"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Client ID *
          </label>
          <Input
            type="text"
            value={config.oauthClientId}
            onChange={(e) => onChange('oauthClientId', e.target.value)}
            placeholder="Your OAuth client ID"
            className={errors.oauth_client_id ? 'border-theme-error' : ''}
          />
          {errors.oauth_client_id && (
            <p className="mt-1 text-sm text-theme-error">{errors.oauth_client_id}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Client Secret
          </label>
          <Input
            type="password"
            value={config.oauthClientSecret}
            onChange={(e) => onChange('oauthClientSecret', e.target.value)}
            placeholder="Your OAuth client secret (optional for public clients)"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Authorization URL *
          </label>
          <Input
            type="url"
            value={config.oauthAuthorizationUrl}
            onChange={(e) => onChange('oauthAuthorizationUrl', e.target.value)}
            placeholder="https://provider.com/oauth/authorize"
            className={errors.oauth_authorization_url ? 'border-theme-error' : ''}
          />
          {errors.oauth_authorization_url && (
            <p className="mt-1 text-sm text-theme-error">{errors.oauth_authorization_url}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Token URL *
          </label>
          <Input
            type="url"
            value={config.oauthTokenUrl}
            onChange={(e) => onChange('oauthTokenUrl', e.target.value)}
            placeholder="https://provider.com/oauth/token"
            className={errors.oauth_token_url ? 'border-theme-error' : ''}
          />
          {errors.oauth_token_url && (
            <p className="mt-1 text-sm text-theme-error">{errors.oauth_token_url}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Scopes
          </label>
          <Input
            type="text"
            value={config.oauthScopes}
            onChange={(e) => onChange('oauthScopes', e.target.value)}
            placeholder="read write (space-separated)"
          />
          <p className="mt-1 text-xs text-theme-tertiary">
            Space-separated list of OAuth scopes required by the MCP server
          </p>
        </div>
      </div>
    )}
  </div>
);
