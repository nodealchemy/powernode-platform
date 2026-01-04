import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  RefreshCw,
  Puzzle,
  Download,
  Trash2,
  Power,
  PowerOff,
  ExternalLink,
  Star,
  Shield,
  Package,
  Search
} from 'lucide-react';
import { pluginsApi, Plugin } from '@/features/plugins/services/pluginsApi';

export const AdminPluginsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [plugins, setPlugins] = useState<Plugin[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [typeFilter, setTypeFilter] = useState<string>('all');

  const loadPlugins = useCallback(async () => {
    try {
      setLoading(true);
      const filters: { status?: string; type?: string } = {};
      if (statusFilter !== 'all') filters.status = statusFilter;
      if (typeFilter !== 'all') filters.type = typeFilter;

      const response = await pluginsApi.getPlugins(filters);
      setPlugins(response?.plugins || []);
    } catch (error) {
      showNotification('Failed to load plugins', 'error');
    } finally {
      setLoading(false);
    }
  }, [statusFilter, typeFilter, showNotification]);

  useEffect(() => {
    loadPlugins();
  }, [loadPlugins]);

  // Check permissions
  const canManagePlugins = hasPermissions(user, ['admin.plugins.manage', 'admin.access']);
  const canReadPlugins = hasPermissions(user, ['admin.plugins.read', 'admin.access']);

  if (!canReadPlugins) {
    return <Navigate to="/app" replace />;
  }

  const handleInstallPlugin = async (plugin: Plugin) => {
    try {
      await pluginsApi.installPlugin(plugin.id);
      showNotification(`Plugin "${plugin.name}" installed successfully`, 'success');
      loadPlugins();
    } catch (error) {
      showNotification('Failed to install plugin', 'error');
    }
  };

  const handleUninstallPlugin = (plugin: Plugin) => {
    confirm({
      title: 'Uninstall Plugin',
      message: `Are you sure you want to uninstall "${plugin.name}"? This will remove all plugin functionality.`,
      confirmLabel: 'Uninstall',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await pluginsApi.uninstallPlugin(plugin.id);
          showNotification(`Plugin "${plugin.name}" uninstalled successfully`, 'success');
          loadPlugins();
        } catch (error) {
          showNotification('Failed to uninstall plugin', 'error');
        }
      }
    });
  };

  const handleDeletePlugin = (plugin: Plugin) => {
    confirm({
      title: 'Delete Plugin',
      message: `Are you sure you want to delete "${plugin.name}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await pluginsApi.deletePlugin(plugin.id);
          showNotification(`Plugin "${plugin.name}" deleted successfully`, 'success');
          loadPlugins();
        } catch (error) {
          showNotification('Failed to delete plugin', 'error');
        }
      }
    });
  };

  const filteredPlugins = plugins.filter(plugin =>
    plugin.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    plugin.description?.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadPlugins,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Admin', href: '/app/admin', icon: '⚙️' },
    { label: 'Plugins', icon: '🧩' }
  ];

  const getInstallationStatus = (plugin: Plugin) => {
    const installation = plugin.plugin_installations?.[0];
    if (!installation) return null;
    return installation.status;
  };

  const isInstalled = (plugin: Plugin) => {
    const status = getInstallationStatus(plugin);
    return status === 'active' || status === 'inactive';
  };

  return (
    <PageContainer
      title="Plugin Management"
      description="Manage installed plugins and extensions"
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      {/* Filters */}
      <div className="mb-6 flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-secondary" />
          <input
            type="text"
            placeholder="Search plugins..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder:text-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
        >
          <option value="all">All Statuses</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
          <option value="deprecated">Deprecated</option>
        </select>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
        >
          <option value="all">All Types</option>
          <option value="ai_provider">AI Provider</option>
          <option value="workflow_node">Workflow Node</option>
          <option value="integration">Integration</option>
          <option value="extension">Extension</option>
        </select>
      </div>

      {loading ? (
        <div className="flex items-center justify-center h-64">
          <LoadingSpinner size="lg" message="Loading plugins..." />
        </div>
      ) : filteredPlugins.length === 0 ? (
        <Card className="p-12 text-center">
          <Puzzle className="h-12 w-12 text-theme-secondary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">No Plugins Found</h3>
          <p className="text-theme-secondary">
            {searchQuery ? 'No plugins match your search criteria.' : 'No plugins are installed yet.'}
          </p>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {filteredPlugins.map((plugin) => (
            <Card key={plugin.id} className="p-6 hover:shadow-lg transition-shadow">
              <div className="flex items-start justify-between mb-4">
                <div className="flex items-center gap-3">
                  <div className="p-2 bg-theme-interactive-primary/10 rounded-lg">
                    <Package className="h-6 w-6 text-theme-interactive-primary" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="font-semibold text-theme-primary">{plugin.name}</h3>
                      {plugin.is_official && (
                        <span title="Official Plugin">
                          <Shield className="h-4 w-4 text-theme-success" />
                        </span>
                      )}
                      {plugin.is_verified && (
                        <span title="Verified">
                          <Star className="h-4 w-4 text-theme-warning fill-current" />
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-theme-muted">v{plugin.version} by {plugin.author}</p>
                  </div>
                </div>
                <Badge variant={pluginsApi.getStatusColor(plugin.status)} size="sm">
                  {plugin.status}
                </Badge>
              </div>

              <p className="text-sm text-theme-secondary mb-4 line-clamp-2">
                {plugin.description || 'No description available'}
              </p>

              {/* Capabilities */}
              {plugin.capabilities && plugin.capabilities.length > 0 && (
                <div className="mb-4">
                  <div className="flex flex-wrap gap-1">
                    {plugin.capabilities.slice(0, 3).map((cap) => (
                      <Badge key={cap} variant="outline" size="xs">
                        {cap.replace(/_/g, ' ')}
                      </Badge>
                    ))}
                    {plugin.capabilities.length > 3 && (
                      <Badge variant="outline" size="xs">
                        +{plugin.capabilities.length - 3}
                      </Badge>
                    )}
                  </div>
                </div>
              )}

              {/* Stats */}
              <div className="flex items-center gap-4 mb-4 text-sm text-theme-secondary">
                {plugin.install_count !== undefined && (
                  <span className="flex items-center gap-1">
                    <Download className="h-3 w-3" />
                    {plugin.install_count} installs
                  </span>
                )}
                {plugin.average_rating !== undefined && (
                  <span className="flex items-center gap-1">
                    <Star className="h-3 w-3" />
                    {plugin.average_rating.toFixed(1)}
                  </span>
                )}
                <span className="text-theme-muted">
                  {pluginsApi.getSourceTypeLabel(plugin.source_type)}
                </span>
              </div>

              {/* Actions */}
              <div className="flex items-center justify-between pt-4 border-t border-theme">
                <div className="flex items-center gap-2">
                  {plugin.homepage && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => window.open(plugin.homepage, '_blank')}
                    >
                      <ExternalLink className="h-3 w-3" />
                    </Button>
                  )}
                </div>

                {canManagePlugins && (
                  <div className="flex items-center gap-2">
                    {isInstalled(plugin) ? (
                      <>
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => handleUninstallPlugin(plugin)}
                        >
                          <PowerOff className="h-3 w-3 mr-1" />
                          Uninstall
                        </Button>
                      </>
                    ) : (
                      <Button
                        variant="primary"
                        size="sm"
                        onClick={() => handleInstallPlugin(plugin)}
                      >
                        <Power className="h-3 w-3 mr-1" />
                        Install
                      </Button>
                    )}
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleDeletePlugin(plugin)}
                      className="text-theme-danger hover:bg-theme-danger/10"
                    >
                      <Trash2 className="h-3 w-3" />
                    </Button>
                  </div>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}
      {ConfirmationDialog}
    </PageContainer>
  );
};

export default AdminPluginsPage;
