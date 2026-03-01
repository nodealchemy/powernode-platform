import React, { useState, useEffect } from 'react';
import { X, Key, Eye, EyeOff } from 'lucide-react';
import { AvailableProvider, CreateCredentialData, GitCredential } from '../types';
import { useGitCredentials } from '../hooks/useGitProviders';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';

interface CredentialModalProps {
  isOpen: boolean;
  onClose: () => void;
  provider: AvailableProvider;
  onSuccess: () => void;
  credential?: GitCredential | null; // If provided, we're editing
}

export const CredentialModal: React.FC<CredentialModalProps> = ({
  isOpen,
  onClose,
  provider,
  onSuccess,
  credential,
}) => {
  const isEditing = !!credential;
  const { createCredential, updateCredential } = useGitCredentials(provider.id);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showToken, setShowToken] = useState(false);

  const [formData, setFormData] = useState<{
    name: string;
    auth_type: 'oauth' | 'personal_access_token';
    access_token: string;
    is_active: boolean;
  }>({
    name: '',
    auth_type: 'personal_access_token',
    access_token: '',
    is_active: true,
  });

  // Reset form when modal opens or credential changes
  useEffect(() => {
    if (isOpen) {
      if (credential) {
        // Editing existing credential
        setFormData({
          name: credential.name,
          auth_type: credential.auth_type,
          access_token: '', // Don't pre-fill token for security
          is_active: credential.is_active,
        });
      } else {
        // Creating new credential
        setFormData({
          name: `${provider.name} Token`,
          auth_type: 'personal_access_token',
          access_token: '',
          is_active: true,
        });
      }
      setError(null);
      setShowToken(false);
    }
  }, [isOpen, credential, provider.name]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    // For creating, token is always required
    // For editing, token is optional (only update if provided)
    if (!isEditing && !formData.access_token) {
      setError('Access token is required');
      return;
    }

    try {
      setLoading(true);

      if (isEditing && credential) {
        // Update existing credential
        const updateData: Partial<{
          name: string;
          is_active: boolean;
          credentials?: { access_token: string };
        }> = {
          name: formData.name,
          is_active: formData.is_active,
        };

        // Only include credentials if a new token was provided
        if (formData.access_token) {
          updateData.credentials = { access_token: formData.access_token };
        }

        await updateCredential(credential.id, updateData);
      } else {
        // Create new credential - URLs are inherited from the provider
        const credentialData: CreateCredentialData = {
          name: formData.name,
          auth_type: formData.auth_type,
          credentials: {
            access_token: formData.access_token,
          },
          is_active: true,
          is_default: true,
        };

        await createCredential(credentialData);
      }

      onSuccess();
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : isEditing
            ? 'Failed to update credential'
            : 'Failed to create credential'
      );
    } finally {
      setLoading(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div className="fixed inset-0 bg-black/50 z-0" onClick={onClose} />

      {/* Modal */}
      <div className="relative z-10 bg-theme-surface rounded-lg shadow-xl w-full max-w-md mx-4 border border-theme">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <h2 className="text-lg font-semibold text-theme-primary">
            {isEditing ? `Edit ${credential?.name}` : `Connect ${provider.name}`}
          </h2>
          <button
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-theme-hover text-theme-secondary"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="p-4 space-y-4">
          {error && <ErrorAlert message={error} />}

          {/* Name */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Credential Name
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) =>
                setFormData({ ...formData, name: e.target.value })
              }
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              placeholder="My GitHub Token"
              required
            />
          </div>

          {/* Access Token */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              <Key className="w-4 h-4 inline mr-1" />
              Personal Access Token
              {isEditing && (
                <span className="text-theme-secondary font-normal ml-1">
                  (leave empty to keep current)
                </span>
              )}
            </label>
            <div className="relative">
              <input
                type={showToken ? 'text' : 'password'}
                value={formData.access_token}
                onChange={(e) =>
                  setFormData({ ...formData, access_token: e.target.value })
                }
                className="w-full px-3 py-2 pr-10 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary font-mono text-sm"
                placeholder={isEditing ? '••••••••••••' : 'ghp_xxxxxxxxxxxx'}
                required={!isEditing}
              />
              <button
                type="button"
                onClick={() => setShowToken(!showToken)}
                className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-theme-secondary hover:text-theme-primary"
              >
                {showToken ? (
                  <EyeOff className="w-4 h-4" />
                ) : (
                  <Eye className="w-4 h-4" />
                )}
              </button>
            </div>
            {!isEditing && (
              <p className="text-xs text-theme-secondary mt-1">
                {provider.provider_type === 'github' &&
                  'Create a token at GitHub → Settings → Developer settings → Personal access tokens'}
                {provider.provider_type === 'gitlab' &&
                  'Create a token at GitLab → Preferences → Access Tokens'}
                {provider.provider_type === 'gitea' &&
                  'Create a token at Settings → Applications → Generate New Token'}
              </p>
            )}
          </div>

          {/* Active Status (only when editing) */}
          {isEditing && (
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="is_active"
                checked={formData.is_active}
                onChange={(e) =>
                  setFormData({ ...formData, is_active: e.target.checked })
                }
                className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
              />
              <label
                htmlFor="is_active"
                className="text-sm text-theme-primary cursor-pointer"
              >
                Credential is active
              </label>
            </div>
          )}

          {/* Actions */}
          <div className="flex gap-3 pt-4">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 btn-theme btn-theme-outline"
              disabled={loading}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="flex-1 btn-theme btn-theme-primary"
              disabled={loading}
            >
              {loading
                ? isEditing
                  ? 'Saving...'
                  : 'Connecting...'
                : isEditing
                  ? 'Save Changes'
                  : 'Connect'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default CredentialModal;
