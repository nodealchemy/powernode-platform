import { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import type { McpServer } from '@/pages/app/ai/McpBrowserPage';
import { StdioConfigFields } from './StdioConfigFields';
import { WebSocketConfigFields } from './WebSocketConfigFields';
import { OAuthConfigFields, type OAuthConfig } from './OAuthConfigFields';
import { EnvVarEditor } from './EnvVarEditor';

export interface McpServerFormData {
  name: string;
  description?: string;
  connection_type: 'stdio' | 'websocket' | 'http';
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  auth_type?: 'none' | 'api_key' | 'oauth2';
  oauth_provider?: string;
  oauth_client_id?: string;
  oauth_client_secret?: string;
  oauth_authorization_url?: string;
  oauth_token_url?: string;
  oauth_scopes?: string;
}

export interface McpServerFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: McpServerFormData) => Promise<void>;
  server?: McpServer | null;
}

export const McpServerFormModal: React.FC<McpServerFormModalProps> = ({
  isOpen,
  onClose,
  onSubmit,
  server
}) => {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [connectionType, setConnectionType] = useState<'stdio' | 'websocket' | 'http'>('stdio');
  const [command, setCommand] = useState('');
  const [args, setArgs] = useState<string[]>([]);
  const [envVars, setEnvVars] = useState<{ key: string; value: string }[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});

  const [oauthConfig, setOauthConfig] = useState<OAuthConfig>({
    authType: 'none',
    oauthProvider: '',
    oauthClientId: '',
    oauthClientSecret: '',
    oauthAuthorizationUrl: '',
    oauthTokenUrl: '',
    oauthScopes: '',
  });

  const isEditing = !!server;

  useEffect(() => {
    if (server) {
      setName(server.name);
      setDescription(server.description || '');
      setConnectionType(server.connection_type as 'stdio' | 'websocket' | 'http');
      setCommand('');
      setArgs([]);
      setEnvVars([]);
      setOauthConfig({
        authType: (server as McpServer & { auth_type?: string }).auth_type as 'none' | 'api_key' | 'oauth2' || 'none',
        oauthProvider: '',
        oauthClientId: '',
        oauthClientSecret: '',
        oauthAuthorizationUrl: '',
        oauthTokenUrl: '',
        oauthScopes: '',
      });
    } else {
      setName('');
      setDescription('');
      setConnectionType('stdio');
      setCommand('');
      setArgs([]);
      setEnvVars([]);
      setOauthConfig({
        authType: 'none',
        oauthProvider: '',
        oauthClientId: '',
        oauthClientSecret: '',
        oauthAuthorizationUrl: '',
        oauthTokenUrl: '',
        oauthScopes: '',
      });
    }
    setErrors({});
  }, [server, isOpen]);

  const validateForm = () => {
    const newErrors: Record<string, string> = {};

    if (!name.trim()) {
      newErrors.name = 'Name is required';
    }

    if (connectionType === 'stdio' && !command.trim()) {
      newErrors.command = 'Command is required for stdio connections';
    }

    if (connectionType !== 'stdio' && !command.trim()) {
      newErrors.command = 'URL is required for HTTP/WebSocket connections';
    }

    if (oauthConfig.authType === 'oauth2') {
      if (!oauthConfig.oauthClientId.trim()) {
        newErrors.oauth_client_id = 'Client ID is required for OAuth2';
      }
      if (!oauthConfig.oauthAuthorizationUrl.trim()) {
        newErrors.oauth_authorization_url = 'Authorization URL is required for OAuth2';
      }
      if (!oauthConfig.oauthTokenUrl.trim()) {
        newErrors.oauth_token_url = 'Token URL is required for OAuth2';
      }
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validateForm()) {
      return;
    }

    setSubmitting(true);
    try {
      const env: Record<string, string> = {};
      envVars.forEach(({ key, value }) => {
        if (key.trim()) {
          env[key.trim()] = value;
        }
      });

      await onSubmit({
        name: name.trim(),
        description: description.trim() || undefined,
        connection_type: connectionType,
        command: command.trim(),
        args: args.filter(a => a.trim()),
        env: Object.keys(env).length > 0 ? env : undefined,
        auth_type: oauthConfig.authType,
        oauth_provider: oauthConfig.oauthProvider.trim() || undefined,
        oauth_client_id: oauthConfig.oauthClientId.trim() || undefined,
        oauth_client_secret: oauthConfig.oauthClientSecret.trim() || undefined,
        oauth_authorization_url: oauthConfig.oauthAuthorizationUrl.trim() || undefined,
        oauth_token_url: oauthConfig.oauthTokenUrl.trim() || undefined,
        oauth_scopes: oauthConfig.oauthScopes.trim() || undefined
      });
    } finally {
      setSubmitting(false);
    }
  };

  const handleOAuthChange = <K extends keyof OAuthConfig>(field: K, value: OAuthConfig[K]) => {
    setOauthConfig(prev => ({ ...prev, [field]: value }));
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit MCP Server' : 'Add MCP Server'}
      size="lg"
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Server Name *
            </label>
            <Input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g., Calculator, Filesystem, Weather"
              className={errors.name ? 'border-theme-error' : ''}
            />
            {errors.name && (
              <p className="mt-1 text-sm text-theme-error">{errors.name}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Description
            </label>
            <Input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Optional description of what this server does"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Connection Type *
            </label>
            <Select
              value={connectionType}
              onChange={(value) => setConnectionType(value as 'stdio' | 'websocket' | 'http')}
            >
              <option value="stdio">STDIO (Local Process)</option>
              <option value="http">HTTP (Remote URL)</option>
              <option value="websocket">WebSocket (Remote URL)</option>
            </Select>
          </div>
        </div>

        <div className="border-t border-theme pt-4 space-y-4">
          <h3 className="text-sm font-medium text-theme-primary">Connection Configuration</h3>

          {connectionType === 'stdio' ? (
            <StdioConfigFields
              command={command}
              onCommandChange={setCommand}
              commandError={errors.command}
              args={args}
              onArgsChange={setArgs}
            />
          ) : (
            <WebSocketConfigFields
              url={command}
              onUrlChange={setCommand}
              urlError={errors.command}
              connectionType={connectionType}
            />
          )}

          <EnvVarEditor
            envVars={envVars}
            onEnvVarsChange={setEnvVars}
          />
        </div>

        <OAuthConfigFields
          config={oauthConfig}
          onChange={handleOAuthChange}
          errors={errors}
        />

        <div className="flex items-center justify-end gap-3 pt-4 border-t border-theme">
          <Button
            type="button"
            variant="outline"
            onClick={onClose}
            disabled={submitting}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            variant="primary"
            disabled={submitting}
          >
            {submitting ? (isEditing ? 'Updating...' : 'Creating...') : (isEditing ? 'Update Server' : 'Create Server')}
          </Button>
        </div>
      </form>
    </Modal>
  );
};
