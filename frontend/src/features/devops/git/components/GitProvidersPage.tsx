import React, { useState } from 'react';
import { GitBranch, Plus, RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useGitProviders } from '../hooks/useGitProviders';
import { GitProviderCard } from './GitProviderCard';
import { CredentialModal } from './CredentialModal';
import { GitProviderModal } from './GitProviderModal';
import { ProviderCredentialsPanel } from './ProviderCredentialsPanel';
import { AvailableProvider, GitProviderDetail, GitCredential } from '../types';
import { gitProvidersApi } from '../services/gitProvidersApi';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotification } from '@/shared/hooks/useNotification';

export const GitProvidersPage: React.FC = () => {
  const { currentUser } = useAuth();
  const { showNotification } = useNotification();
  const { availableProviders, loading, error, refreshAvailable } =
    useGitProviders();

  // Credential modal state
  const [selectedProvider, setSelectedProvider] =
    useState<AvailableProvider | null>(null);
  const [isCredentialModalOpen, setIsCredentialModalOpen] = useState(false);
  const [editingCredential, setEditingCredential] = useState<GitCredential | null>(null);

  // Credentials panel state
  const [isCredentialsPanelOpen, setIsCredentialsPanelOpen] = useState(false);

  // Provider modal state
  const [isProviderModalOpen, setIsProviderModalOpen] = useState(false);
  const [editingProvider, setEditingProvider] = useState<GitProviderDetail | null>(null);

  const canManageProviders = currentUser?.permissions?.includes(
    'git.providers.create'
  );

  const handleManageCredentials = (provider: AvailableProvider) => {
    setSelectedProvider(provider);
    if (provider.configured) {
      // Show credentials panel for configured providers
      setIsCredentialsPanelOpen(true);
    } else {
      // Go straight to add credential for unconfigured providers
      setEditingCredential(null);
      setIsCredentialModalOpen(true);
    }
  };

  const handleAddCredentialFromPanel = () => {
    // Open add modal from credentials panel
    setEditingCredential(null);
    setIsCredentialsPanelOpen(false);
    setIsCredentialModalOpen(true);
  };

  const handleEditCredential = (credential: GitCredential) => {
    setEditingCredential(credential);
    setIsCredentialsPanelOpen(false);
    setIsCredentialModalOpen(true);
  };

  const handleCredentialsPanelClose = () => {
    setIsCredentialsPanelOpen(false);
    setSelectedProvider(null);
  };

  const handleCredentialModalClose = () => {
    setIsCredentialModalOpen(false);
    setEditingCredential(null);
    // If we came from the credentials panel, go back to it
    if (selectedProvider?.configured) {
      setIsCredentialsPanelOpen(true);
    } else {
      setSelectedProvider(null);
    }
  };

  const handleCredentialSaved = () => {
    setIsCredentialModalOpen(false);
    setEditingCredential(null);
    refreshAvailable();
    showNotification({
      type: 'success',
      message: editingCredential
        ? 'Credential updated successfully'
        : 'Git credential created successfully',
    });
    // If we came from the credentials panel, go back to it
    if (selectedProvider?.configured) {
      setIsCredentialsPanelOpen(true);
    } else {
      setSelectedProvider(null);
    }
  };

  const handleAddProvider = () => {
    setEditingProvider(null);
    setIsProviderModalOpen(true);
  };

  const handleEditProvider = async (provider: AvailableProvider) => {
    try {
      const fullProvider = await gitProvidersApi.getProvider(provider.id);
      setEditingProvider(fullProvider);
      setIsProviderModalOpen(true);
    } catch (err) {
      showNotification({
        type: 'error',
        message: 'Failed to load provider details',
      });
    }
  };

  const handleDeleteProvider = async (provider: AvailableProvider) => {
    if (!confirm(`Are you sure you want to delete "${provider.name}"? This will also remove all credentials associated with this provider.`)) {
      return;
    }

    try {
      await gitProvidersApi.deleteProvider(provider.id);
      refreshAvailable();
      showNotification({
        type: 'success',
        message: `Provider "${provider.name}" deleted successfully`,
      });
    } catch (err) {
      showNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to delete provider',
      });
    }
  };

  const handleProviderModalClose = () => {
    setIsProviderModalOpen(false);
    setEditingProvider(null);
  };

  const handleProviderSaved = () => {
    setIsProviderModalOpen(false);
    setEditingProvider(null);
    refreshAvailable();
    showNotification({
      type: 'success',
      message: editingProvider ? 'Provider updated successfully' : 'Provider added successfully',
    });
  };

  const actions = [
    {
      id: 'add',
      label: 'Add Provider',
      onClick: handleAddProvider,
      variant: 'primary' as const,
      icon: Plus,
      disabled: !canManageProviders,
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refreshAvailable,
      variant: 'outline' as const,
      icon: RefreshCw,
    },
  ];

  if (loading) {
    return (
      <PageContainer
        title="Git Providers"
        description="Manage your Git provider integrations"
        breadcrumbs={[
          { label: 'System', href: '/app/system' },
          { label: 'Git Providers' },
        ]}
      >
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
        </div>
      </PageContainer>
    );
  }

  if (error) {
    return (
      <PageContainer
        title="Git Providers"
        description="Manage your Git provider integrations"
        breadcrumbs={[
          { label: 'System', href: '/app/system' },
          { label: 'Git Providers' },
        ]}
      >
        <div className="bg-theme-error/10 border border-theme-error rounded-lg p-4">
          <p className="text-theme-error">{error}</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Git Providers"
      description="Connect and manage your Git provider integrations for repository management and CI/CD"
      breadcrumbs={[
        { label: 'System', href: '/app/system' },
        { label: 'Git Providers' },
      ]}
      actions={actions}
    >
      {/* Providers Grid */}
      {availableProviders.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {availableProviders.map((provider) => (
            <GitProviderCard
              key={provider.id}
              provider={provider}
              onAddCredential={() => handleManageCredentials(provider)}
              onEdit={() => handleEditProvider(provider)}
              onDelete={() => handleDeleteProvider(provider)}
              canManage={canManageProviders}
            />
          ))}
        </div>
      ) : (
        <div className="text-center py-12">
          <GitBranch className="w-12 h-12 mx-auto text-theme-secondary mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">
            No Git Providers
          </h3>
          <p className="text-theme-secondary mb-4">
            Add a Git provider to connect your repositories.
          </p>
          {canManageProviders && (
            <button
              onClick={handleAddProvider}
              className="btn-theme btn-theme-primary inline-flex items-center gap-2"
            >
              <Plus className="w-4 h-4" />
              Add Provider
            </button>
          )}
        </div>
      )}

      {/* Credentials Panel */}
      {selectedProvider && (
        <ProviderCredentialsPanel
          isOpen={isCredentialsPanelOpen}
          onClose={handleCredentialsPanelClose}
          provider={selectedProvider}
          onAddCredential={handleAddCredentialFromPanel}
          onEditCredential={handleEditCredential}
        />
      )}

      {/* Credential Modal */}
      {selectedProvider && (
        <CredentialModal
          isOpen={isCredentialModalOpen}
          onClose={handleCredentialModalClose}
          provider={selectedProvider}
          onSuccess={handleCredentialSaved}
          credential={editingCredential}
        />
      )}

      {/* Provider Modal */}
      <GitProviderModal
        isOpen={isProviderModalOpen}
        onClose={handleProviderModalClose}
        onSuccess={handleProviderSaved}
        provider={editingProvider}
      />
    </PageContainer>
  );
};

export default GitProvidersPage;
