import { useState, useEffect } from 'react';
import type { IntegrationTemplate, IntegrationCredential, CredentialFormData, CredentialType } from '../../types';
import { integrationsApi } from '../../services/integrationsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface CredentialStepProps {
  template: IntegrationTemplate;
  selectedCredential: IntegrationCredential | null;
  onSelect: (credential: IntegrationCredential | null) => void;
  onBack: () => void;
}

export function CredentialStep({
  template,
  selectedCredential,
  onSelect,
  onBack,
}: CredentialStepProps) {
  const { showNotification } = useNotifications();
  const [credentials, setCredentials] = useState<IntegrationCredential[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [selected, setSelected] = useState<string | null>(selectedCredential?.id || null);

  // Form state for new credential
  const [formData, setFormData] = useState<CredentialFormData>({
    name: '',
    credential_type: 'api_key',
    credentials: {},
    scopes: [],
  });

  useEffect(() => {
    loadCredentials();
  }, []);

  const loadCredentials = async () => {
    setIsLoading(true);
    const response = await integrationsApi.getCredentials(1, 100);
    if (response.success && response.data) {
      setCredentials(response.data.credentials);
    }
    setIsLoading(false);
  };

  const handleCreateCredential = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsCreating(true);

    const response = await integrationsApi.createCredential(formData);
    if (response.success && response.data) {
      showNotification('Credential created successfully', 'success');
      setCredentials((prev) => [...prev, response.data!.credential]);
      setSelected(response.data.credential.id);
      setShowCreateForm(false);
      setFormData({
        name: '',
        credential_type: 'api_key',
        credentials: {},
        scopes: [],
      });
    } else {
      showNotification(response.error || 'Failed to create credential', 'error');
    }
    setIsCreating(false);
  };

  const handleNext = () => {
    const credential = credentials.find((c) => c.id === selected) || null;
    onSelect(credential);
  };

  const handleSkip = () => {
    onSelect(null);
  };

  const credentialRequirements = template.credential_requirements || {};
  const isCredentialRequired = Object.keys(credentialRequirements).length > 0;

  const credentialTypes: { value: CredentialType; label: string }[] = [
    { value: 'api_key', label: 'API Key' },
    { value: 'bearer_token', label: 'Bearer Token' },
    { value: 'basic', label: 'Basic Auth' },
    { value: 'oauth2', label: 'OAuth 2.0' },
    { value: 'github_app', label: 'GitHub App' },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-theme-primary">Configure Credentials</h2>
        <p className="text-sm text-theme-secondary mt-1">
          {isCredentialRequired
            ? 'This integration requires credentials to authenticate'
            : 'Optionally add credentials for this integration'}
        </p>
      </div>

      {/* Credential Requirements */}
      {Object.keys(credentialRequirements).length > 0 && (
        <div className="p-4 bg-theme-surface rounded-lg">
          <h3 className="text-sm font-medium text-theme-primary mb-2">
            Required Credentials
          </h3>
          <ul className="space-y-1">
            {Object.entries(credentialRequirements).map(([key, value]) => (
              <li key={key} className="text-sm text-theme-secondary">
                • {key}: {String(value)}
              </li>
            ))}
          </ul>
        </div>
      )}

      {isLoading ? (
        <div className="flex items-center justify-center py-8">
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-theme-primary border-t-transparent" />
        </div>
      ) : showCreateForm ? (
        <form onSubmit={handleCreateCredential} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Credential Name
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              placeholder="My API Key"
              required
              className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Credential Type
            </label>
            <select
              value={formData.credential_type}
              onChange={(e) =>
                setFormData({
                  ...formData,
                  credential_type: e.target.value as CredentialType,
                  credentials: {},
                })
              }
              className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            >
              {credentialTypes.map((type) => (
                <option key={type.value} value={type.value}>
                  {type.label}
                </option>
              ))}
            </select>
          </div>

          {/* Dynamic fields based on credential type */}
          {formData.credential_type === 'api_key' && (
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                API Key
              </label>
              <input
                type="password"
                value={formData.credentials.api_key || ''}
                onChange={(e) =>
                  setFormData({
                    ...formData,
                    credentials: { ...formData.credentials, api_key: e.target.value },
                  })
                }
                placeholder="sk-..."
                required
                className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              />
            </div>
          )}

          {formData.credential_type === 'bearer_token' && (
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Token
              </label>
              <input
                type="password"
                value={formData.credentials.token || ''}
                onChange={(e) =>
                  setFormData({
                    ...formData,
                    credentials: { ...formData.credentials, token: e.target.value },
                  })
                }
                placeholder="Bearer token..."
                required
                className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              />
            </div>
          )}

          {formData.credential_type === 'basic' && (
            <>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Username
                </label>
                <input
                  type="text"
                  value={formData.credentials.username || ''}
                  onChange={(e) =>
                    setFormData({
                      ...formData,
                      credentials: { ...formData.credentials, username: e.target.value },
                    })
                  }
                  required
                  className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Password
                </label>
                <input
                  type="password"
                  value={formData.credentials.password || ''}
                  onChange={(e) =>
                    setFormData({
                      ...formData,
                      credentials: { ...formData.credentials, password: e.target.value },
                    })
                  }
                  required
                  className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                />
              </div>
            </>
          )}

          <div className="flex justify-end gap-3">
            <button
              type="button"
              onClick={() => setShowCreateForm(false)}
              className="px-4 py-2 text-theme-secondary hover:text-theme-primary transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isCreating}
              className="px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover disabled:opacity-50 transition-colors"
            >
              {isCreating ? 'Creating...' : 'Create Credential'}
            </button>
          </div>
        </form>
      ) : (
        <>
          {/* Existing Credentials List */}
          <div className="space-y-2">
            {credentials.length === 0 ? (
              <p className="text-sm text-theme-secondary text-center py-4">
                No credentials found. Create one to continue.
              </p>
            ) : (
              credentials.map((credential) => (
                <label
                  key={credential.id}
                  className={`flex items-center gap-3 p-4 border rounded-lg cursor-pointer transition-colors ${
                    selected === credential.id
                      ? 'border-theme-primary bg-theme-primary bg-opacity-5'
                      : 'border-theme hover:border-theme-secondary'
                  }`}
                >
                  <input
                    type="radio"
                    name="credential"
                    value={credential.id}
                    checked={selected === credential.id}
                    onChange={() => setSelected(credential.id)}
                    className="text-theme-primary focus:ring-theme-primary"
                  />
                  <div className="flex-1">
                    <p className="font-medium text-theme-primary">{credential.name}</p>
                    <p className="text-sm text-theme-secondary">
                      {credential.credential_type} •{' '}
                      {credential.expires_at
                        ? `Expires ${new Date(credential.expires_at).toLocaleDateString()}`
                        : 'No expiration'}
                    </p>
                  </div>
                  {credential.is_default && (
                    <span className="px-2 py-1 text-xs bg-theme-surface text-theme-secondary rounded">
                      Default
                    </span>
                  )}
                </label>
              ))
            )}
          </div>

          <button
            onClick={() => setShowCreateForm(true)}
            className="w-full py-2 border-2 border-dashed border-theme text-theme-secondary hover:border-theme-primary hover:text-theme-primary rounded-lg transition-colors"
          >
            + Create New Credential
          </button>
        </>
      )}

      {/* Actions */}
      {!showCreateForm && (
        <div className="flex justify-between pt-4 border-t border-theme">
          <button
            onClick={onBack}
            className="px-4 py-2 text-theme-secondary hover:text-theme-primary transition-colors"
          >
            Back
          </button>
          <div className="flex gap-3">
            {!isCredentialRequired && (
              <button
                onClick={handleSkip}
                className="px-4 py-2 text-theme-secondary hover:text-theme-primary transition-colors"
              >
                Skip
              </button>
            )}
            <button
              onClick={handleNext}
              disabled={isCredentialRequired && !selected}
              className="px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
