import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Package, Search, Filter, RefreshCw, Brain, Zap, CheckCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { pluginsApi } from '@/shared/services/ai';
import type { Plugin } from '@/shared/types/plugin';
import { PluginCard } from './PluginCard';
import { PluginFilters } from './PluginFilters';
import { PluginDetailModal } from './PluginDetailModal';

export const PluginsPage: React.FC = () => {
  const navigate = useNavigate();
  const [plugins, setPlugins] = useState<Plugin[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [selectedPluginId, setSelectedPluginId] = useState<string | null>(null);
  const [filters, setFilters] = useState({
    type: undefined,
    status: 'available',
    verified: undefined,
    official: undefined
  });

  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();

  const canBrowsePlugins = hasPermission('ai.plugins.browse');
  const canInstallPlugins = hasPermission('ai.plugins.install');

  const loadPlugins = useCallback(async (showSpinner = true) => {
    if (!canBrowsePlugins) return;

    try {
      if (showSpinner) setLoading(true);
      else setRefreshing(true);

      const response = await pluginsApi.listPlugins({
        ...filters,
        search: searchQuery || undefined
      });

      setPlugins(response);
    } catch (error) {
      console.error('Failed to load plugins:', error);
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load plugins. Please try again.'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [filters, searchQuery, canBrowsePlugins, addNotification]);

  useEffect(() => {
    loadPlugins();
  }, [loadPlugins]);

  const handleSearch = useCallback((query: string) => {
    setSearchQuery(query);
  }, []);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleFilterChange = useCallback((newFilters: any) => {
    setFilters(prev => ({ ...prev, ...newFilters }));
  }, []);

  const handleRefresh = useCallback(() => {
    loadPlugins(false);
  }, [loadPlugins]);

  const handleViewDetails = useCallback((pluginId: string) => {
    setSelectedPluginId(pluginId);
  }, []);

  const handleInstall = useCallback((pluginId: string) => {
    if (!canInstallPlugins) {
      addNotification({
        type: 'error',
        title: 'Permission Denied',
        message: 'You do not have permission to install plugins'
      });
      return;
    }
    // Open detail modal which has install functionality
    setSelectedPluginId(pluginId);
  }, [canInstallPlugins, addNotification]);

  const handleInstallSuccess = useCallback(() => {
    loadPlugins(false);
  }, [loadPlugins]);

  const pageActions = [
    {
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'outline' as const,
      icon: RefreshCw,
      disabled: refreshing,
      size: 'sm' as const
    },
    {
      label: 'Marketplaces',
      onClick: () => navigate('/app/ai/plugins/marketplace'),
      variant: 'outline' as const,
      icon: Package,
      size: 'sm' as const
    },
    {
      label: 'Installed Plugins',
      onClick: () => navigate('/app/ai/plugins/installed'),
      variant: 'primary' as const,
      icon: Package,
      size: 'sm' as const
    }
  ];

  if (!canBrowsePlugins) {
    return (
      <PageContainer title="Plugins">
        <EmptyState
          icon={Package}
          title="Permission Required"
          description="You don't have permission to browse plugins"
        />
      </PageContainer>
    );
  }

  if (loading) {
    return (
      <PageContainer
        title="AI Plugins"
        description="Browse and install AI providers, workflow nodes, and integrations"
      >
        <LoadingSpinner className="py-12" />
      </PageContainer>
    );
  }

  const aiProviderCount = plugins.filter(p => p.plugin_types.includes('ai_provider')).length;
  const workflowNodeCount = plugins.filter(p => p.plugin_types.includes('workflow_node')).length;
  const verifiedCount = plugins.filter(p => p.is_verified).length;

  return (
    <PageContainer
      title="AI Plugins"
      description="Browse and install AI providers, workflow nodes, and integrations"
      actions={pageActions}
    >
      {/* Summary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Total Plugins</p>
              <p className="text-2xl font-semibold text-theme-primary">{plugins.length}</p>
            </div>
            <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
              <Package className="h-5 w-5 text-theme-info" />
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">AI Providers</p>
              <p className="text-2xl font-semibold text-theme-primary">{aiProviderCount}</p>
            </div>
            <div className="h-10 w-10 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
              <Brain className="h-5 w-5 text-theme-success" />
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Workflow Nodes</p>
              <p className="text-2xl font-semibold text-theme-primary">{workflowNodeCount}</p>
            </div>
            <div className="h-10 w-10 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
              <Zap className="h-5 w-5 text-theme-warning" />
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Verified</p>
              <p className="text-2xl font-semibold text-theme-primary">{verifiedCount}</p>
            </div>
            <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
              <CheckCircle className="h-5 w-5 text-theme-info" />
            </div>
          </div>
        </Card>
      </div>

      {/* Search and Filters */}
      <div className="mb-6">
        <div className="flex items-center gap-4 mb-4">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
            <Input
              placeholder="Search plugins by name, description, or capabilities..."
              value={searchQuery}
              onChange={(e) => handleSearch(e.target.value)}
              className="pl-10"
            />
          </div>

          <Button
            variant="outline"
            onClick={() => setShowFilters(!showFilters)}
            className="flex items-center gap-2"
          >
            <Filter className="h-4 w-4" />
            Filters
          </Button>
        </div>

        {showFilters && (
          <PluginFilters
            filters={filters}
            onFiltersChange={handleFilterChange}
          />
        )}
      </div>

      {/* Plugins Grid */}
      {plugins.length === 0 ? (
        <EmptyState
          icon={Package}
          title="No plugins found"
          description="Try adjusting your search or filters"
          action={
            <Button onClick={() => { setSearchQuery(''); setFilters({ type: undefined, status: 'available', verified: undefined, official: undefined }); }}>
              Clear Filters
            </Button>
          }
        />
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-6">
          {plugins.map((plugin) => (
            <PluginCard
              key={plugin.id}
              plugin={plugin}
              showInstallButton={canInstallPlugins}
              onViewDetails={handleViewDetails}
              onInstall={handleInstall}
            />
          ))}
        </div>
      )}

      {/* Detail Modal */}
      {selectedPluginId && (
        <PluginDetailModal
          pluginId={selectedPluginId}
          isOpen={!!selectedPluginId}
          onClose={() => setSelectedPluginId(null)}
          onInstallSuccess={handleInstallSuccess}
        />
      )}
    </PageContainer>
  );
};
