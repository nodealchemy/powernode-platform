import React, { useState, useEffect } from 'react';
import { Plus, HardDrive } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { StorageProviderCard } from '@/features/system/storage/components/StorageProviderCard';
import { StorageProviderModal } from '@/features/system/storage/components/StorageProviderModal';
import { ConnectionTestModal } from '@/features/system/storage/components/ConnectionTestModal';
import { storageApi } from '@/features/system/storage/services/storageApi';
import { StorageProvider, StorageProviderFormData, StorageConnectionTestResult } from '@/shared/types/storage';
import { useAuth } from '@/shared/hooks/useAuth';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';

const StorageProvidersPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { currentUser } = useAuth();
  const { confirm, ConfirmationDialog } = useConfirmation();
  usePageWebSocket({ pageType: 'system' });
  const [providers, setProviders] = useState<StorageProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [, setRefreshing] = useState(false);
  const [showModal, setShowModal] = useState(false);
  const [editingProvider, setEditingProvider] = useState<StorageProvider | null>(null);
  const [saving, setSaving] = useState(false);
  const [testingId, setTestingId] = useState<string | null>(null);
  const [showTestModal, setShowTestModal] = useState(false);
  const [testingProvider, setTestingProvider] = useState<StorageProvider | null>(null);
  const [testResult, setTestResult] = useState<StorageConnectionTestResult | null>(null);

  // Check permissions
  const canManage = currentUser?.permissions?.includes('admin.storage.manage');
  const canRead = currentUser?.permissions?.includes('admin.storage.read') || canManage;

  const loadProviders = async () => {
    try {
      setRefreshing(true);
      const data = await storageApi.getProviders();
      setProviders(data);
    } catch (_error) {
      dispatch(addNotification({ type: 'error', message: 'Failed to load storage providers' }));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const { refreshAction } = useRefreshAction({
    onRefresh: loadProviders,
    loading,
  });

  useEffect(() => {
    if (canRead) {
      loadProviders();
    } else {
      setLoading(false);
    }
  }, [canRead]);

  const handleAddProvider = () => {
    setEditingProvider(null);
    setShowModal(true);
  };

  const handleEditProvider = async (provider: StorageProvider) => {
    try {
      // Fetch full provider details including configuration
      const fullProvider = await storageApi.getProvider(provider.id);
      setEditingProvider(fullProvider);
      setShowModal(true);
    } catch (_error) {
      dispatch(addNotification({ type: 'error', message: 'Failed to load provider configuration' }));
    }
  };

  const handleDeleteProvider = (provider: StorageProvider) => {
    confirm({
      title: 'Delete Storage Provider',
      message: `Are you sure you want to delete "${provider.name}"?`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await storageApi.deleteProvider(provider.id);
          dispatch(addNotification({ type: 'success', message: 'Storage provider deleted successfully' }));
          await loadProviders();
        } catch (_error) {
          dispatch(addNotification({ type: 'error', message: 'Failed to delete storage provider' }));
        }
      },
    });
  };

  const handleTestConnection = async (provider: StorageProvider) => {
    setTestingProvider(provider);
    setTestResult(null);
    setShowTestModal(true);
    setTestingId(provider.id);

    try {
      const result = await storageApi.testConnection(provider.id);
      setTestResult(result);
      await loadProviders();
    } catch (error) {
      setTestResult({
        success: false,
        message: 'Failed to test connection',
        details: {
          error: error instanceof Error ? error.message : 'Unknown error occurred',
        },
      });
    } finally {
      setTestingId(null);
    }
  };

  const handleCloseTestModal = () => {
    setShowTestModal(false);
    setTestingProvider(null);
    setTestResult(null);
  };

  const handleSetDefault = async (provider: StorageProvider) => {
    try {
      await storageApi.setDefault(provider.id);
      dispatch(addNotification({ type: 'success', message: `"${provider.name}" set as default storage provider` }));
      await loadProviders();
    } catch (_error) {
      dispatch(addNotification({ type: 'error', message: 'Failed to set default provider' }));
    }
  };

  const handleSaveProvider = async (data: StorageProviderFormData) => {
    setSaving(true);
    try {
      if (editingProvider) {
        await storageApi.updateProvider(editingProvider.id, data);
        dispatch(addNotification({ type: 'success', message: 'Storage provider updated successfully' }));
      } else {
        await storageApi.createProvider(data);
        dispatch(addNotification({ type: 'success', message: 'Storage provider created successfully' }));
      }
      setShowModal(false);
      setEditingProvider(null);
      await loadProviders();
    } catch (_error) {
      dispatch(addNotification({
        type: 'error',
        message: editingProvider
          ? 'Failed to update storage provider'
          : 'Failed to create storage provider'
      }));
    } finally {
      setSaving(false);
    }
  };

  if (!canRead) {
    return (
      <PageContainer
        title="File Storage"
        description="Manage storage providers"
      >
        <div className="text-center py-12">
          <p className="text-theme-secondary">
            You don't have permission to view storage providers.
          </p>
        </div>
      </PageContainer>
    );
  }

  return (
    <>
      <PageContainer
        title="File Storage"
        description="Configure storage providers for file management"
        breadcrumbs={[
          { label: 'Dashboard', href: '/dashboard' },
          { label: 'System', href: '/system' },
          { label: 'File Storage', href: '/system/storage' }
        ]}
        actions={
          canManage
            ? [
                refreshAction,
                {
                  id: 'add-provider',
                  label: 'Add Provider',
                  onClick: handleAddProvider,
                  variant: 'primary',
                  icon: Plus,
                },
              ]
            : [refreshAction]
        }
      >
        <div className="space-y-6">
          {/* Overview Stats */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-sm text-theme-secondary mb-1">Total Providers</p>
              <p className="text-2xl font-bold text-theme-primary">{providers.length}</p>
            </div>
            <div className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-sm text-theme-secondary mb-1">Active Providers</p>
              <p className="text-2xl font-bold text-theme-success">
                {providers.filter((p) => p.status === 'active').length}
              </p>
            </div>
            <div className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-sm text-theme-secondary mb-1">Total Files</p>
              <p className="text-2xl font-bold text-theme-primary">
                {providers
                  .reduce((sum, p) => sum + (p.usage_stats?.total_files || 0), 0)
                  .toLocaleString()}
              </p>
            </div>
          </div>

          {/* Storage Providers Grid */}
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="animate-spin h-8 w-8 border-4 border-theme-info border-t-transparent rounded-full" />
            </div>
          ) : providers.length === 0 ? (
            <div className="bg-theme-surface border border-theme rounded-lg p-12 text-center">
              <HardDrive className="h-12 w-12 text-theme-secondary mx-auto mb-4" />
              <h3 className="text-lg font-semibold text-theme-primary mb-2">
                No Storage Providers
              </h3>
              <p className="text-theme-secondary mb-6">
                Get started by adding your first storage provider
              </p>
              {canManage && (
                <button
                  onClick={handleAddProvider}
                  className="btn-theme btn-theme-primary inline-flex items-center gap-2"
                >
                  <Plus className="h-4 w-4" />
                  Add Storage Provider
                </button>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              {providers.map((provider) => (
                <StorageProviderCard
                  key={provider.id}
                  provider={provider}
                  onEdit={handleEditProvider}
                  onDelete={handleDeleteProvider}
                  onTest={handleTestConnection}
                  onSetDefault={handleSetDefault}
                  testing={testingId === provider.id}
                />
              ))}
            </div>
          )}

          {/* Information Panel */}
          <div className="bg-theme-info/10 dark:bg-theme-info/20 border border-theme-info/30 dark:border-theme-info/50 rounded-lg p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-2">
              About Storage Providers
            </h3>
            <div className="text-sm text-theme-secondary space-y-2">
              <p>
                Storage providers define where files uploaded to the platform are stored. You can
                configure multiple providers and set one as the default.
              </p>
              <ul className="list-disc list-inside space-y-1 ml-2">
                <li>
                  <strong>Local Storage:</strong> Store files on the server's filesystem
                </li>
                <li>
                  <strong>Amazon S3:</strong> Store files in AWS S3 buckets (or S3-compatible
                  services)
                </li>
                <li>
                  <strong>Azure Blob Storage:</strong> Store files in Microsoft Azure
                </li>
                <li>
                  <strong>Google Cloud Storage:</strong> Store files in Google Cloud Platform
                </li>
              </ul>
              <p className="mt-3">
                <strong>Note:</strong> Credentials are encrypted and stored securely. Use the "Test
                Connection" feature to verify your configuration.
              </p>
            </div>
          </div>
        </div>
      </PageContainer>

      {/* Configuration Modal */}
      {canManage && (
        <StorageProviderModal
          isOpen={showModal}
          onClose={() => {
            setShowModal(false);
            setEditingProvider(null);
          }}
          onSave={handleSaveProvider}
          provider={editingProvider}
          saving={saving}
        />
      )}

      {ConfirmationDialog}

      {/* Connection Test Modal */}
      <ConnectionTestModal
        isOpen={showTestModal}
        onClose={handleCloseTestModal}
        providerName={testingProvider?.name || ''}
        result={testResult}
        testing={testingId !== null}
      />
    </>
  );
};

export default StorageProvidersPage;
