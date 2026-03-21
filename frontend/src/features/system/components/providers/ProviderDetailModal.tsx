import React, { useState, useEffect, useCallback } from 'react';
import {
  X,
  Cloud,
  MapPin,
  Server,
  Settings,
  Globe,
  Lock,
  CheckCircle,
  XCircle,
  Plus,
  Edit2,
  Trash2,
  RefreshCw
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { systemApi } from '@/features/system/services/systemApi';
import { RegionFormModal } from './RegionFormModal';
import { ConnectionFormModal } from './ConnectionFormModal';
import type { SystemProvider, SystemProviderRegion, SystemProviderConnection } from '@/features/system/types/system.types';

interface ProviderDetailModalProps {
  providerId: string | null;
  isOpen: boolean;
  onClose: () => void;
  onEdit?: (provider: SystemProvider) => void;
}

type TabId = 'info' | 'regions' | 'connections' | 'config';

const providerTypeLabels: Record<string, string> = {
  aws: 'Amazon Web Services',
  openstack: 'OpenStack',
  gcp: 'Google Cloud Platform',
  azure: 'Microsoft Azure',
  digitalocean: 'DigitalOcean',
  custom: 'Custom Provider'
};

/**
 * ProviderDetailModal - Modal for viewing provider details with tabs
 */
export const ProviderDetailModal: React.FC<ProviderDetailModalProps> = ({
  providerId,
  isOpen,
  onClose,
  onEdit
}) => {
  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();

  // Permission checks
  const canManageRegions = hasPermission('system.regions.create');
  const canDeleteRegions = hasPermission('system.regions.delete');
  const canManageConnections = hasPermission('system.connections.create');
  const canDeleteConnections = hasPermission('system.connections.delete');
  const canTestConnections = hasPermission('system.connections.test');

  const [provider, setProvider] = useState<SystemProvider | null>(null);
  const [regions, setRegions] = useState<SystemProviderRegion[]>([]);
  const [connections, setConnections] = useState<SystemProviderConnection[]>([]);
  const [loading, setLoading] = useState(false);
  const [activeTab, setActiveTab] = useState<TabId>('info');

  // Region modal state
  const [showRegionModal, setShowRegionModal] = useState(false);
  const [editRegion, setEditRegion] = useState<SystemProviderRegion | null>(null);
  const [regionToDelete, setRegionToDelete] = useState<SystemProviderRegion | null>(null);
  const [deletingRegion, setDeletingRegion] = useState(false);

  // Connection modal state
  const [showConnectionModal, setShowConnectionModal] = useState(false);
  const [editConnection, setEditConnection] = useState<SystemProviderConnection | null>(null);
  const [connectionToDelete, setConnectionToDelete] = useState<SystemProviderConnection | null>(null);
  const [deletingConnection, setDeletingConnection] = useState(false);
  const [testingConnection, setTestingConnection] = useState<string | null>(null);

  useEffect(() => {
    if (isOpen && providerId) {
      setLoading(true);
      setActiveTab('info');

      Promise.all([
        systemApi.getProvider(providerId),
        systemApi.getProviderRegions(providerId),
        systemApi.getProviderConnections()
      ])
        .then(([providerData, regionsData, connectionsData]) => {
          setProvider(providerData);
          setRegions(regionsData);
          // Filter connections for this provider
          setConnections(connectionsData.filter(c => c.provider_id === providerId));
        })
        .catch(() => {
          setProvider(null);
          setRegions([]);
          setConnections([]);
        })
        .finally(() => {
          setLoading(false);
        });
    }
  }, [isOpen, providerId]);

  // Refresh data
  const refreshData = useCallback(async () => {
    if (!providerId) return;

    try {
      const [regionsData, connectionsData] = await Promise.all([
        systemApi.getProviderRegions(providerId),
        systemApi.getProviderConnections()
      ]);
      setRegions(regionsData);
      setConnections(connectionsData.filter(c => c.provider_id === providerId));
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to refresh data'
      });
    }
  }, [providerId, addNotification]);

  // Region handlers
  const handleAddRegion = useCallback(() => {
    setEditRegion(null);
    setShowRegionModal(true);
  }, []);

  const handleEditRegion = useCallback((region: SystemProviderRegion) => {
    setEditRegion(region);
    setShowRegionModal(true);
  }, []);

  const handleDeleteRegion = useCallback(async () => {
    if (!providerId || !regionToDelete) return;

    setDeletingRegion(true);
    try {
      await systemApi.deleteProviderRegion(providerId, regionToDelete.id);
      addNotification({
        type: 'success',
        message: `Region "${regionToDelete.name}" deleted successfully`
      });
      setRegionToDelete(null);
      await refreshData();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete region: ${errorMessage}`
      });
    } finally {
      setDeletingRegion(false);
    }
  }, [providerId, regionToDelete, addNotification, refreshData]);

  // Connection handlers
  const handleAddConnection = useCallback(() => {
    setEditConnection(null);
    setShowConnectionModal(true);
  }, []);

  const handleEditConnection = useCallback((connection: SystemProviderConnection) => {
    setEditConnection(connection);
    setShowConnectionModal(true);
  }, []);

  const handleDeleteConnection = useCallback(async () => {
    if (!connectionToDelete) return;

    setDeletingConnection(true);
    try {
      await systemApi.deleteProviderConnection(connectionToDelete.id);
      addNotification({
        type: 'success',
        message: `Connection "${connectionToDelete.name}" deleted successfully`
      });
      setConnectionToDelete(null);
      await refreshData();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to delete connection: ${errorMessage}`
      });
    } finally {
      setDeletingConnection(false);
    }
  }, [connectionToDelete, addNotification, refreshData]);

  const handleTestConnection = useCallback(async (connection: SystemProviderConnection) => {
    setTestingConnection(connection.id);
    try {
      const result = await systemApi.testProviderConnection(connection.id);
      if (result.success) {
        addNotification({
          type: 'success',
          message: result.message || 'Connection test successful'
        });
      } else {
        addNotification({
          type: 'error',
          message: result.message || 'Connection test failed'
        });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Connection test failed: ${errorMessage}`
      });
    } finally {
      setTestingConnection(null);
    }
  }, [addNotification]);

  if (!isOpen) return null;

  const tabs = [
    { id: 'info' as const, label: 'Information', icon: Cloud },
    { id: 'regions' as const, label: 'Regions', icon: MapPin, count: regions.length },
    { id: 'connections' as const, label: 'Connections', icon: Server, count: connections.length },
    { id: 'config' as const, label: 'Configuration', icon: Settings }
  ];

  const renderInfoTab = () => {
    if (!provider) return null;

    return (
      <div className="space-y-6">
        {/* Basic Info */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
          <div className="space-y-4">
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Name</label>
              <p className="text-theme-primary font-medium">{provider.name}</p>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Description</label>
              <p className="text-theme-primary">{provider.description || '—'}</p>
            </div>
          </div>
          <div className="space-y-4">
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Provider Type</label>
              <p className="text-theme-primary">
                {providerTypeLabels[provider.provider_type] || provider.provider_type}
              </p>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Resources</label>
              <div className="flex items-center gap-4 text-theme-primary">
                <span>{provider.region_count || 0} regions</span>
                <span>{provider.connection_count || 0} connections</span>
              </div>
            </div>
          </div>
        </div>

        {/* Status Badges */}
        <div className="flex flex-wrap gap-4 pt-4 border-t border-theme">
          <div className="flex items-center gap-2">
            {provider.enabled ? (
              <CheckCircle className="w-5 h-5 text-theme-success" />
            ) : (
              <XCircle className="w-5 h-5 text-theme-error" />
            )}
            <span className="text-theme-primary">
              {provider.enabled ? 'Enabled' : 'Disabled'}
            </span>
          </div>
          <div className="flex items-center gap-2">
            {provider.public ? (
              <Globe className="w-5 h-5 text-theme-info" />
            ) : (
              <Lock className="w-5 h-5 text-theme-secondary" />
            )}
            <span className="text-theme-primary">
              {provider.public ? 'Public' : 'Private'}
            </span>
          </div>
        </div>

        {/* Timestamps */}
        <div className="grid grid-cols-2 gap-4 pt-4 border-t border-theme text-sm">
          <div>
            <span className="text-theme-secondary">Created:</span>
            <span className="ml-2 text-theme-primary">
              {new Date(provider.created_at).toLocaleString()}
            </span>
          </div>
          <div>
            <span className="text-theme-secondary">Updated:</span>
            <span className="ml-2 text-theme-primary">
              {new Date(provider.updated_at).toLocaleString()}
            </span>
          </div>
        </div>
      </div>
    );
  };

  const renderRegionsTab = () => {
    return (
      <div className="space-y-4">
        {/* Header with Add button */}
        {canManageRegions && (
          <div className="flex justify-end">
            <Button variant="primary" size="sm" onClick={handleAddRegion}>
              <Plus className="w-4 h-4 mr-2" />
              Add Region
            </Button>
          </div>
        )}

        {regions.length === 0 ? (
          <div className="text-center py-12">
            <MapPin className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
            <p className="text-theme-secondary">No regions configured</p>
            <p className="text-sm text-theme-tertiary mt-1">
              Add regions to define deployment locations
            </p>
          </div>
        ) : (
          regions.map(region => (
            <div
              key={region.id}
              className="bg-theme-background rounded-lg p-4 border border-theme"
            >
              <div className="flex items-start justify-between mb-2">
                <div>
                  <h4 className="font-medium text-theme-primary">{region.name}</h4>
                  {region.region_code && (
                    <p className="text-sm text-theme-secondary">{region.region_code}</p>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-sm text-theme-secondary">
                    {region.zone_count || 0} zones • {region.instance_type_count || 0} instance types
                  </span>
                  {canManageRegions && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleEditRegion(region)}
                      title="Edit region"
                    >
                      <Edit2 className="w-4 h-4" />
                    </Button>
                  )}
                  {canDeleteRegions && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setRegionToDelete(region)}
                      title="Delete region"
                      className="text-theme-error hover:text-theme-error"
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  )}
                </div>
              </div>
              {region.description && (
                <p className="text-sm text-theme-secondary mt-2">{region.description}</p>
              )}
              {region.endpoint_url && (
                <p className="text-xs text-theme-tertiary mt-2 font-mono">
                  {region.endpoint_url}
                </p>
              )}
            </div>
          ))
        )}
      </div>
    );
  };

  const renderConnectionsTab = () => {
    return (
      <div className="space-y-4">
        {/* Header with Add button */}
        {canManageConnections && (
          <div className="flex justify-end">
            <Button variant="primary" size="sm" onClick={handleAddConnection}>
              <Plus className="w-4 h-4 mr-2" />
              Add Connection
            </Button>
          </div>
        )}

        {connections.length === 0 ? (
          <div className="text-center py-12">
            <Server className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
            <p className="text-theme-secondary">No connections configured</p>
            <p className="text-sm text-theme-tertiary mt-1">
              Add connections to authenticate with this provider
            </p>
          </div>
        ) : (
          connections.map(connection => (
            <div
              key={connection.id}
              className="bg-theme-background rounded-lg p-4 border border-theme"
            >
              <div className="flex items-start justify-between mb-2">
                <div>
                  <h4 className="font-medium text-theme-primary">{connection.name}</h4>
                  {connection.endpoint_url && (
                    <p className="text-xs text-theme-tertiary font-mono mt-1">
                      {connection.endpoint_url}
                    </p>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <Badge variant="success" size="xs">Active</Badge>
                  {canTestConnections && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleTestConnection(connection)}
                      disabled={testingConnection === connection.id}
                      title="Test connection"
                    >
                      {testingConnection === connection.id ? (
                        <RefreshCw className="w-4 h-4 animate-spin" />
                      ) : (
                        <RefreshCw className="w-4 h-4" />
                      )}
                    </Button>
                  )}
                  {canManageConnections && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleEditConnection(connection)}
                      title="Edit connection"
                    >
                      <Edit2 className="w-4 h-4" />
                    </Button>
                  )}
                  {canDeleteConnections && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setConnectionToDelete(connection)}
                      title="Delete connection"
                      className="text-theme-error hover:text-theme-error"
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  )}
                </div>
              </div>
              {connection.description && (
                <p className="text-sm text-theme-secondary mt-2">{connection.description}</p>
              )}
            </div>
          ))
        )}
      </div>
    );
  };

  const renderConfigTab = () => {
    if (!provider) return null;

    const hasConfig = provider.config && Object.keys(provider.config).length > 0;
    const hasCapabilities = provider.capabilities && Object.keys(provider.capabilities).length > 0;

    return (
      <div className="space-y-6">
        {/* Config */}
        <div>
          <h4 className="font-medium text-theme-primary mb-2">Configuration</h4>
          {hasConfig ? (
            <pre className="bg-theme-background rounded-lg p-4 text-sm text-theme-primary overflow-x-auto border border-theme font-mono">
              {JSON.stringify(provider.config, null, 2)}
            </pre>
          ) : (
            <p className="text-theme-secondary text-sm">No configuration defined</p>
          )}
        </div>

        {/* Capabilities */}
        <div>
          <h4 className="font-medium text-theme-primary mb-2">Capabilities</h4>
          {hasCapabilities ? (
            <pre className="bg-theme-background rounded-lg p-4 text-sm text-theme-primary overflow-x-auto border border-theme font-mono">
              {JSON.stringify(provider.capabilities, null, 2)}
            </pre>
          ) : (
            <p className="text-theme-secondary text-sm">No capabilities defined</p>
          )}
        </div>
      </div>
    );
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="fixed inset-0 bg-black/50 transition-opacity" onClick={onClose} />

      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-3xl bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <Cloud className="w-6 h-6 text-theme-accent" />
              <div>
                <h2 className="text-lg font-semibold text-theme-primary">
                  {loading ? 'Loading...' : provider?.name || 'Provider Details'}
                </h2>
                {provider && (
                  <p className="text-sm text-theme-secondary">
                    {providerTypeLabels[provider.provider_type] || provider.provider_type}
                  </p>
                )}
              </div>
            </div>
            <div className="flex items-center gap-2">
              {provider && onEdit && (
                <Button variant="outline" size="sm" onClick={() => onEdit(provider)}>
                  Edit
                </Button>
              )}
              <Button variant="ghost" size="sm" onClick={onClose}>
                <X className="w-5 h-5" />
              </Button>
            </div>
          </div>

          {/* Tabs */}
          <div className="border-b border-theme">
            <nav className="flex -mb-px">
              {tabs.map(tab => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center gap-2 px-6 py-3 text-sm font-medium border-b-2 transition-colors ${
                    activeTab === tab.id
                      ? 'border-theme-accent text-theme-accent'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-tertiary'
                  }`}
                >
                  <tab.icon className="w-4 h-4" />
                  {tab.label}
                  {tab.count !== undefined && tab.count > 0 && (
                    <span className="ml-1 px-1.5 py-0.5 text-xs bg-theme-background rounded">
                      {tab.count}
                    </span>
                  )}
                </button>
              ))}
            </nav>
          </div>

          {/* Content */}
          <div className="p-6 max-h-[60vh] overflow-y-auto">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <LoadingSpinner size="lg" />
              </div>
            ) : provider ? (
              <>
                {activeTab === 'info' && renderInfoTab()}
                {activeTab === 'regions' && renderRegionsTab()}
                {activeTab === 'connections' && renderConnectionsTab()}
                {activeTab === 'config' && renderConfigTab()}
              </>
            ) : (
              <div className="text-center py-12">
                <p className="text-theme-error">Failed to load provider details</p>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex justify-end p-4 border-t border-theme">
            <Button variant="outline" onClick={onClose}>
              Close
            </Button>
          </div>
        </div>
      </div>

      {/* Region Form Modal */}
      {providerId && (
        <RegionFormModal
          providerId={providerId}
          region={editRegion}
          isOpen={showRegionModal}
          onClose={() => {
            setShowRegionModal(false);
            setEditRegion(null);
          }}
          onRegionSaved={refreshData}
        />
      )}

      {/* Connection Form Modal */}
      {providerId && (
        <ConnectionFormModal
          providerId={providerId}
          connection={editConnection}
          isOpen={showConnectionModal}
          onClose={() => {
            setShowConnectionModal(false);
            setEditConnection(null);
          }}
          onConnectionSaved={refreshData}
        />
      )}

      {/* Region Delete Confirmation */}
      {regionToDelete && (
        <div className="fixed inset-0 z-[60] overflow-y-auto">
          <div
            className="fixed inset-0 bg-black/50 transition-opacity"
            onClick={() => setRegionToDelete(null)}
          />
          <div className="flex min-h-full items-center justify-center p-4">
            <div className="relative w-full max-w-md bg-theme-surface rounded-lg shadow-xl">
              <div className="p-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-2">
                  Delete Region
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete the region "{regionToDelete.name}"? This action cannot be undone.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => setRegionToDelete(null)}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteRegion}
                    disabled={deletingRegion}
                  >
                    {deletingRegion ? 'Deleting...' : 'Delete Region'}
                  </Button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Connection Delete Confirmation */}
      {connectionToDelete && (
        <div className="fixed inset-0 z-[60] overflow-y-auto">
          <div
            className="fixed inset-0 bg-black/50 transition-opacity"
            onClick={() => setConnectionToDelete(null)}
          />
          <div className="flex min-h-full items-center justify-center p-4">
            <div className="relative w-full max-w-md bg-theme-surface rounded-lg shadow-xl">
              <div className="p-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-2">
                  Delete Connection
                </h3>
                <p className="text-theme-secondary mb-6">
                  Are you sure you want to delete the connection "{connectionToDelete.name}"? This action cannot be undone.
                </p>
                <div className="flex justify-end gap-3">
                  <Button
                    variant="outline"
                    onClick={() => setConnectionToDelete(null)}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={handleDeleteConnection}
                    disabled={deletingConnection}
                  >
                    {deletingConnection ? 'Deleting...' : 'Delete Connection'}
                  </Button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ProviderDetailModal;
