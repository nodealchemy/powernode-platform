import React, { useState, useEffect, useCallback } from 'react';
import { Card, Button, Badge, Modal, LoadingSpinner } from '@/shared/components/ui';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { api } from '@/shared/services/api';
import { getErrorMessage } from '@/shared/utils/errorHandling';

interface ApiKey {
  id: string;
  name: string;
  key_preview: string;
  scopes: string[];
  status: 'active' | 'inactive' | 'revoked';
  last_used_at?: string;
  expires_at?: string;
  created_at: string;
}

export const ApiKeyManager: React.FC = () => {
  const { addNotification } = useNotifications();
  const [loading, setLoading] = useState(true);
  const [apiKeys, setApiKeys] = useState<ApiKey[]>([]);
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [newKeyName, setNewKeyName] = useState('');
  const [selectedScopes, setSelectedScopes] = useState<string[]>([]);
  const [isCreating, setIsCreating] = useState(false);
  const [newKey, setNewKey] = useState<string | null>(null);

  const availableScopes = [
    { id: 'subscriptions:read', label: 'Read Subscriptions' },
    { id: 'subscriptions:write', label: 'Write Subscriptions' },
    { id: 'billing:read', label: 'Read Billing' },
    { id: 'billing:write', label: 'Write Billing' },
    { id: 'usage:read', label: 'Read Usage' },
    { id: 'usage:write', label: 'Write Usage' },
    { id: 'webhooks:manage', label: 'Manage Webhooks' },
    { id: 'analytics:read', label: 'Read Analytics' },
  ];

  const loadApiKeys = useCallback(async () => {
    setLoading(true);
    try {
      const response = await api.get('/api/v1/api_keys');
      if (response.data.success) {
        setApiKeys(response.data.data || []);
      }
    } catch (error) {
      addNotification({ type: 'error', message: getErrorMessage(error) });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadApiKeys();
  }, [loadApiKeys]);

  const handleCreateKey = async () => {
    if (!newKeyName.trim()) {
      addNotification({ type: 'error', message: 'Please enter a name for the API key' });
      return;
    }

    setIsCreating(true);
    try {
      const response = await api.post('/api/v1/api_keys', {
        name: newKeyName,
        scopes: selectedScopes,
      });

      if (response.data.success) {
        setNewKey(response.data.data.full_key);
        loadApiKeys();
        addNotification({ type: 'success', message: 'API key created successfully' });
      }
    } catch (error) {
      addNotification({ type: 'error', message: getErrorMessage(error) });
    } finally {
      setIsCreating(false);
    }
  };

  const handleRevokeKey = async (keyId: string) => {
    if (!confirm('Are you sure you want to revoke this API key? This action cannot be undone.')) {
      return;
    }

    try {
      const response = await api.delete(`/api/v1/api_keys/${keyId}`);
      if (response.data.success) {
        loadApiKeys();
        addNotification({ type: 'success', message: 'API key revoked successfully' });
      }
    } catch (error) {
      addNotification({ type: 'error', message: getErrorMessage(error) });
    }
  };

  const handleCopyKey = async () => {
    if (newKey) {
      await navigator.clipboard.writeText(newKey);
      addNotification({ type: 'success', message: 'API key copied to clipboard' });
    }
  };

  const handleCloseCreateModal = () => {
    setIsCreateModalOpen(false);
    setNewKeyName('');
    setSelectedScopes([]);
    setNewKey(null);
  };

  const formatDate = (dateString?: string) => {
    if (!dateString) return 'Never';
    return new Date(dateString).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <>
      <div className="space-y-6">
        <Card className="p-6">
          <div className="flex items-center justify-between mb-6">
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">API Keys</h3>
              <p className="text-sm text-theme-tertiary">
                Manage your API keys for programmatic access to the Powernode API
              </p>
            </div>
            <Button variant="primary" onClick={() => setIsCreateModalOpen(true)}>
              Create API Key
            </Button>
          </div>

          {apiKeys.length === 0 ? (
            <div className="text-center py-12">
              <svg className="w-16 h-16 mx-auto text-theme-tertiary mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z" />
              </svg>
              <h4 className="text-lg font-medium text-theme-primary mb-2">No API Keys</h4>
              <p className="text-theme-tertiary mb-4">Create your first API key to get started.</p>
              <Button variant="primary" onClick={() => setIsCreateModalOpen(true)}>
                Create API Key
              </Button>
            </div>
          ) : (
            <div className="space-y-4">
              {apiKeys.map((key) => (
                <div
                  key={key.id}
                  className="flex items-center justify-between p-4 rounded-lg bg-theme-surface border border-theme"
                >
                  <div className="flex-1">
                    <div className="flex items-center gap-3 mb-2">
                      <span className="font-medium text-theme-primary">{key.name}</span>
                      <Badge
                        variant={key.status === 'active' ? 'success' : 'error'}
                        size="sm"
                      >
                        {key.status}
                      </Badge>
                    </div>
                    <div className="flex items-center gap-4 text-sm text-theme-tertiary">
                      <code className="bg-theme-hover px-2 py-1 rounded font-mono">
                        {key.key_preview}
                      </code>
                      <span>Created: {formatDate(key.created_at)}</span>
                      <span>Last used: {formatDate(key.last_used_at)}</span>
                    </div>
                    {key.scopes.length > 0 && (
                      <div className="flex flex-wrap gap-1 mt-2">
                        {key.scopes.map((scope) => (
                          <span
                            key={scope}
                            className="text-xs px-2 py-0.5 rounded bg-theme-hover text-theme-secondary"
                          >
                            {scope}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                  <Button
                    variant="danger"
                    size="sm"
                    onClick={() => handleRevokeKey(key.id)}
                    disabled={key.status === 'revoked'}
                  >
                    Revoke
                  </Button>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      <Modal
        isOpen={isCreateModalOpen}
        onClose={handleCloseCreateModal}
        title={newKey ? 'API Key Created' : 'Create API Key'}
      >
        {newKey ? (
          <div className="space-y-4">
            <div className="p-4 rounded-lg bg-amber-50 border border-amber-200">
              <p className="text-sm text-amber-800 mb-2">
                <strong>Important:</strong> Copy your API key now. You won't be able to see it again!
              </p>
            </div>
            <div className="p-4 rounded-lg bg-theme-surface">
              <code className="text-sm font-mono break-all text-theme-primary">{newKey}</code>
            </div>
            <div className="flex justify-end gap-3">
              <Button variant="secondary" onClick={handleCopyKey}>
                Copy Key
              </Button>
              <Button variant="primary" onClick={handleCloseCreateModal}>
                Done
              </Button>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-2">
                Key Name
              </label>
              <input
                type="text"
                value={newKeyName}
                onChange={(e) => setNewKeyName(e.target.value)}
                placeholder="e.g., Production API Key"
                className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-2">
                Scopes (optional)
              </label>
              <div className="grid grid-cols-2 gap-2">
                {availableScopes.map((scope) => (
                  <label
                    key={scope.id}
                    className="flex items-center gap-2 p-2 rounded-lg bg-theme-surface cursor-pointer hover:bg-theme-hover"
                  >
                    <input
                      type="checkbox"
                      checked={selectedScopes.includes(scope.id)}
                      onChange={(e) => {
                        if (e.target.checked) {
                          setSelectedScopes([...selectedScopes, scope.id]);
                        } else {
                          setSelectedScopes(selectedScopes.filter((s) => s !== scope.id));
                        }
                      }}
                      className="rounded border-theme"
                    />
                    <span className="text-sm text-theme-secondary">{scope.label}</span>
                  </label>
                ))}
              </div>
              <p className="text-xs text-theme-tertiary mt-2">
                Leave empty for full access (recommended only for trusted environments)
              </p>
            </div>

            <div className="flex justify-end gap-3 pt-4">
              <Button variant="secondary" onClick={handleCloseCreateModal}>
                Cancel
              </Button>
              <Button
                variant="primary"
                onClick={handleCreateKey}
                disabled={isCreating || !newKeyName.trim()}
              >
                {isCreating ? 'Creating...' : 'Create Key'}
              </Button>
            </div>
          </div>
        )}
      </Modal>
    </>
  );
};
