import React, { useState, useRef } from 'react';
import {
  X,
  Plus,
  Key,
  CheckCircle,
  XCircle,
  MoreVertical,
  Pencil,
  Trash2,
  TestTube,
  Loader2,
} from 'lucide-react';
import { AvailableProvider, GitCredential } from '../types';
import { useGitCredentials } from '../hooks/useGitProviders';
import { useNotification } from '@/shared/hooks/useNotification';

interface ProviderCredentialsPanelProps {
  isOpen: boolean;
  onClose: () => void;
  provider: AvailableProvider;
  onAddCredential: () => void;
  onEditCredential: (credential: GitCredential) => void;
}

export const ProviderCredentialsPanel: React.FC<ProviderCredentialsPanelProps> = ({
  isOpen,
  onClose,
  provider,
  onAddCredential,
  onEditCredential,
}) => {
  const { showNotification } = useNotification();
  const {
    credentials,
    loading,
    deleteCredential,
    testCredential,
    makeDefault,
  } = useGitCredentials(provider.id);

  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState<string | null>(null);
  const [menuPosition, setMenuPosition] = useState<{ top: number; left: number } | null>(null);
  const menuButtonRefs = useRef<Record<string, HTMLButtonElement | null>>({});

  const handleTest = async (credential: GitCredential) => {
    setActionLoading(`test-${credential.id}`);
    try {
      const result = await testCredential(credential.id);
      if (result.success) {
        showNotification({
          type: 'success',
          message: `Connection successful for ${credential.name}`,
        });
      } else {
        showNotification({
          type: 'error',
          message: result.error || 'Connection test failed',
        });
      }
    } catch (err) {
      showNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to test connection',
      });
    } finally {
      setActionLoading(null);
    }
  };

  const handleDelete = async (credential: GitCredential) => {
    if (!confirm(`Are you sure you want to delete "${credential.name}"? This action cannot be undone.`)) {
      return;
    }
    setActionLoading(`delete-${credential.id}`);
    try {
      await deleteCredential(credential.id);
      showNotification({
        type: 'success',
        message: `Credential "${credential.name}" deleted successfully`,
      });
    } catch (err) {
      showNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to delete credential',
      });
    } finally {
      setActionLoading(null);
    }
  };

  const handleMakeDefault = async (credential: GitCredential) => {
    setActionLoading(`default-${credential.id}`);
    try {
      await makeDefault(credential.id);
      showNotification({
        type: 'success',
        message: `"${credential.name}" is now the default credential`,
      });
    } catch (err) {
      showNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to set default credential',
      });
    } finally {
      setActionLoading(null);
    }
  };

  const handleMenuToggle = (credentialId: string) => {
    if (menuOpen === credentialId) {
      setMenuOpen(null);
      setMenuPosition(null);
    } else {
      const button = menuButtonRefs.current[credentialId];
      if (button) {
        const rect = button.getBoundingClientRect();
        setMenuPosition({
          top: rect.bottom + 4,
          left: rect.right - 140, // Menu width is min-w-[140px]
        });
      }
      setMenuOpen(credentialId);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div className="fixed inset-0 bg-black/50 z-0" onClick={onClose} />

      {/* Panel */}
      <div className="relative z-10 bg-theme-surface rounded-lg shadow-xl w-full max-w-lg mx-4 border border-theme max-h-[80vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <div>
            <h2 className="text-lg font-semibold text-theme-primary">
              {provider.name} Credentials
            </h2>
            <p className="text-sm text-theme-secondary">
              Manage authentication credentials for this provider
            </p>
          </div>
          <button
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-theme-hover text-theme-secondary"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-4">
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="w-6 h-6 animate-spin text-theme-primary" />
            </div>
          ) : credentials.length === 0 ? (
            <div className="text-center py-8">
              <Key className="w-10 h-10 mx-auto text-theme-secondary mb-3" />
              <p className="text-theme-secondary mb-4">
                No credentials configured yet
              </p>
              <button
                onClick={onAddCredential}
                className="btn-theme btn-theme-primary btn-theme-sm inline-flex items-center gap-2"
              >
                <Plus className="w-4 h-4" />
                Add Credential
              </button>
            </div>
          ) : (
            <div className="space-y-3">
              {credentials.map((credential) => (
                <div
                  key={credential.id}
                  className="bg-theme-bg rounded-lg border border-theme p-4"
                >
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-3">
                      <div className="p-2 rounded-lg bg-theme-primary/10">
                        <Key className="w-4 h-4 text-theme-primary" />
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="font-medium text-theme-primary">
                            {credential.name}
                          </h3>
                          {credential.is_default && (
                            <span className="px-2 py-0.5 text-xs rounded-full bg-theme-primary/10 text-theme-primary">
                              Default
                            </span>
                          )}
                        </div>
                        <div className="flex items-center gap-2 mt-1">
                          {credential.is_active ? (
                            <span className="flex items-center gap-1 text-xs text-theme-success">
                              <CheckCircle className="w-3 h-3" />
                              Active
                            </span>
                          ) : (
                            <span className="flex items-center gap-1 text-xs text-theme-error">
                              <XCircle className="w-3 h-3" />
                              Inactive
                            </span>
                          )}
                          <span className="text-xs text-theme-secondary">
                            {credential.auth_type.replace('_', ' ')}
                          </span>
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-1">
                      {/* Quick Actions */}
                      <button
                        onClick={() => handleTest(credential)}
                        disabled={actionLoading !== null}
                        className="p-1.5 rounded-lg hover:bg-theme-hover text-theme-secondary hover:text-theme-primary"
                        title="Test Connection"
                      >
                        {actionLoading === `test-${credential.id}` ? (
                          <Loader2 className="w-4 h-4 animate-spin" />
                        ) : (
                          <TestTube className="w-4 h-4" />
                        )}
                      </button>

                      {/* More Menu Button */}
                      <button
                        ref={(el) => { menuButtonRefs.current[credential.id] = el; }}
                        onClick={() => handleMenuToggle(credential.id)}
                        className="p-1.5 rounded-lg hover:bg-theme-hover text-theme-secondary"
                      >
                        <MoreVertical className="w-4 h-4" />
                      </button>
                    </div>
                  </div>

                  {/* Stats */}
                  {(credential.repository_count !== undefined || credential.last_sync_at) && (
                    <div className="mt-3 pt-3 border-t border-theme flex items-center gap-4 text-xs text-theme-secondary">
                      {credential.repository_count !== undefined && (
                        <span>{credential.repository_count} repositories</span>
                      )}
                      {credential.last_sync_at && (
                        <span>
                          Last sync: {new Date(credential.last_sync_at).toLocaleDateString()}
                        </span>
                      )}
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        {credentials.length > 0 && (
          <div className="p-4 border-t border-theme">
            <button
              onClick={onAddCredential}
              className="w-full btn-theme btn-theme-outline btn-theme-sm flex items-center justify-center gap-2"
            >
              <Plus className="w-4 h-4" />
              Add Another Credential
            </button>
          </div>
        )}
      </div>

      {/* Fixed Position Dropdown Menu */}
      {menuOpen && menuPosition && (
        <>
          <div
            className="fixed inset-0 z-[60]"
            onClick={() => {
              setMenuOpen(null);
              setMenuPosition(null);
            }}
          />
          <div
            className="fixed bg-theme-surface border border-theme rounded-lg shadow-lg z-[70] py-1 min-w-[140px]"
            style={{ top: menuPosition.top, left: menuPosition.left }}
          >
            {credentials.find(c => c.id === menuOpen) && (
              <>
                <button
                  onClick={() => {
                    const credential = credentials.find(c => c.id === menuOpen);
                    setMenuOpen(null);
                    setMenuPosition(null);
                    if (credential) onEditCredential(credential);
                  }}
                  className="w-full px-3 py-2 text-left text-sm text-theme-primary hover:bg-theme-hover flex items-center gap-2"
                >
                  <Pencil className="w-4 h-4" />
                  Edit
                </button>
                {!credentials.find(c => c.id === menuOpen)?.is_default && (
                  <button
                    onClick={() => {
                      const credential = credentials.find(c => c.id === menuOpen);
                      setMenuOpen(null);
                      setMenuPosition(null);
                      if (credential) handleMakeDefault(credential);
                    }}
                    className="w-full px-3 py-2 text-left text-sm text-theme-primary hover:bg-theme-hover flex items-center gap-2"
                  >
                    <CheckCircle className="w-4 h-4" />
                    Make Default
                  </button>
                )}
                <button
                  onClick={() => {
                    const credential = credentials.find(c => c.id === menuOpen);
                    setMenuOpen(null);
                    setMenuPosition(null);
                    if (credential) handleDelete(credential);
                  }}
                  className="w-full px-3 py-2 text-left text-sm text-theme-error hover:bg-theme-hover flex items-center gap-2"
                >
                  <Trash2 className="w-4 h-4" />
                  Delete
                </button>
              </>
            )}
          </div>
        </>
      )}
    </div>
  );
};

export default ProviderCredentialsPanel;
