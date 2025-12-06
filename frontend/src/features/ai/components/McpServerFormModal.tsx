import { useState, useEffect } from 'react';
import { Plus, Trash2, Shield, HelpCircle } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import type { McpServer } from '@/pages/app/ai/McpBrowserPage';

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

  // OAuth Configuration
  const [authType, setAuthType] = useState<'none' | 'api_key' | 'oauth2'>('none');
  const [oauthProvider, setOauthProvider] = useState('');
  const [oauthClientId, setOauthClientId] = useState('');
  const [oauthClientSecret, setOauthClientSecret] = useState('');
  const [oauthAuthorizationUrl, setOauthAuthorizationUrl] = useState('');
  const [oauthTokenUrl, setOauthTokenUrl] = useState('');
  const [oauthScopes, setOauthScopes] = useState('');

  const isEditing = !!server;

  // Initialize form when server changes
  useEffect(() => {
    if (server) {
      setName(server.name);
      setDescription(server.description || '');
      setConnectionType(server.connection_type as 'stdio' | 'websocket' | 'http');
      // command/args/env would need to be fetched from API if not in server object
      setCommand('');
      setArgs([]);
      setEnvVars([]);
      // OAuth fields - populated from server object if available
      setAuthType((server as McpServer & { auth_type?: string }).auth_type as 'none' | 'api_key' | 'oauth2' || 'none');
      setOauthProvider('');
      setOauthClientId('');
      setOauthClientSecret('');
      setOauthAuthorizationUrl('');
      setOauthTokenUrl('');
      setOauthScopes('');
    } else {
      setName('');
      setDescription('');
      setConnectionType('stdio');
      setCommand('');
      setArgs([]);
      setEnvVars([]);
      // Reset OAuth fields
      setAuthType('none');
      setOauthProvider('');
      setOauthClientId('');
      setOauthClientSecret('');
      setOauthAuthorizationUrl('');
      setOauthTokenUrl('');
      setOauthScopes('');
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

    // OAuth validation
    if (authType === 'oauth2') {
      if (!oauthClientId.trim()) {
        newErrors.oauth_client_id = 'Client ID is required for OAuth2';
      }
      if (!oauthAuthorizationUrl.trim()) {
        newErrors.oauth_authorization_url = 'Authorization URL is required for OAuth2';
      }
      if (!oauthTokenUrl.trim()) {
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
        // OAuth fields
        auth_type: authType,
        oauth_provider: oauthProvider.trim() || undefined,
        oauth_client_id: oauthClientId.trim() || undefined,
        oauth_client_secret: oauthClientSecret.trim() || undefined,
        oauth_authorization_url: oauthAuthorizationUrl.trim() || undefined,
        oauth_token_url: oauthTokenUrl.trim() || undefined,
        oauth_scopes: oauthScopes.trim() || undefined
      });
    } finally {
      setSubmitting(false);
    }
  };

  const addArg = () => {
    setArgs([...args, '']);
  };

  const removeArg = (index: number) => {
    setArgs(args.filter((_, i) => i !== index));
  };

  const updateArg = (index: number, value: string) => {
    const newArgs = [...args];
    newArgs[index] = value;
    setArgs(newArgs);
  };

  const addEnvVar = () => {
    setEnvVars([...envVars, { key: '', value: '' }]);
  };

  const removeEnvVar = (index: number) => {
    setEnvVars(envVars.filter((_, i) => i !== index));
  };

  const updateEnvVar = (index: number, field: 'key' | 'value', value: string) => {
    const newEnvVars = [...envVars];
    newEnvVars[index][field] = value;
    setEnvVars(newEnvVars);
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit MCP Server' : 'Add MCP Server'}
      size="lg"
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Basic Info */}
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

        {/* Connection Config */}
        <div className="border-t border-theme pt-4 space-y-4">
          <h3 className="text-sm font-medium text-theme-primary">Connection Configuration</h3>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              {connectionType === 'stdio' ? 'Command *' : 'URL *'}
            </label>
            <Input
              type="text"
              value={command}
              onChange={(e) => setCommand(e.target.value)}
              placeholder={
                connectionType === 'stdio'
                  ? 'e.g., node, python, /usr/local/bin/mcp-server'
                  : 'e.g., http://localhost:3100 or wss://mcp.example.com'
              }
              className={errors.command ? 'border-theme-error' : ''}
            />
            {errors.command && (
              <p className="mt-1 text-sm text-theme-error">{errors.command}</p>
            )}
          </div>

          {/* Arguments (for stdio) */}
          {connectionType === 'stdio' && (
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-sm font-medium text-theme-primary">
                  Command Arguments
                </label>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={addArg}
                >
                  <Plus className="h-4 w-4 mr-1" />
                  Add Argument
                </Button>
              </div>
              <div className="space-y-2">
                {args.length === 0 ? (
                  <p className="text-sm text-theme-tertiary">
                    No arguments configured. Click "Add Argument" to add command line arguments.
                  </p>
                ) : (
                  args.map((arg, index) => (
                    <div key={index} className="flex items-center gap-2">
                      <Input
                        type="text"
                        value={arg}
                        onChange={(e) => updateArg(index, e.target.value)}
                        placeholder={`Argument ${index + 1}`}
                        className="flex-1"
                      />
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={() => removeArg(index)}
                        className="text-theme-error"
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  ))
                )}
              </div>
            </div>
          )}

          {/* Environment Variables */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <label className="text-sm font-medium text-theme-primary">
                Environment Variables
              </label>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={addEnvVar}
              >
                <Plus className="h-4 w-4 mr-1" />
                Add Variable
              </Button>
            </div>
            <div className="space-y-2">
              {envVars.length === 0 ? (
                <p className="text-sm text-theme-tertiary">
                  No environment variables configured.
                </p>
              ) : (
                envVars.map((env, index) => (
                  <div key={index} className="flex items-center gap-2">
                    <Input
                      type="text"
                      value={env.key}
                      onChange={(e) => updateEnvVar(index, 'key', e.target.value)}
                      placeholder="Variable name"
                      className="w-1/3"
                    />
                    <span className="text-theme-tertiary">=</span>
                    <Input
                      type="text"
                      value={env.value}
                      onChange={(e) => updateEnvVar(index, 'value', e.target.value)}
                      placeholder="Value"
                      className="flex-1"
                    />
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      onClick={() => removeEnvVar(index)}
                      className="text-theme-error"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>

        {/* Authentication Configuration */}
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
              value={authType}
              onChange={(value) => setAuthType(value as 'none' | 'api_key' | 'oauth2')}
            >
              <option value="none">None (Public)</option>
              <option value="api_key">API Key</option>
              <option value="oauth2">OAuth 2.1</option>
            </Select>
          </div>

          {/* OAuth 2.1 Configuration */}
          {authType === 'oauth2' && (
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
                  value={oauthProvider}
                  onChange={(e) => setOauthProvider(e.target.value)}
                  placeholder="e.g., GitHub, Google, Slack"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Client ID *
                </label>
                <Input
                  type="text"
                  value={oauthClientId}
                  onChange={(e) => setOauthClientId(e.target.value)}
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
                  value={oauthClientSecret}
                  onChange={(e) => setOauthClientSecret(e.target.value)}
                  placeholder="Your OAuth client secret (optional for public clients)"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Authorization URL *
                </label>
                <Input
                  type="url"
                  value={oauthAuthorizationUrl}
                  onChange={(e) => setOauthAuthorizationUrl(e.target.value)}
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
                  value={oauthTokenUrl}
                  onChange={(e) => setOauthTokenUrl(e.target.value)}
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
                  value={oauthScopes}
                  onChange={(e) => setOauthScopes(e.target.value)}
                  placeholder="read write (space-separated)"
                />
                <p className="mt-1 text-xs text-theme-tertiary">
                  Space-separated list of OAuth scopes required by the MCP server
                </p>
              </div>
            </div>
          )}
        </div>

        {/* Actions */}
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
