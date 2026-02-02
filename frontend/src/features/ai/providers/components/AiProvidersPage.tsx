import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Search, Filter, Settings, Zap, AlertCircle, RefreshCw } from 'lucide-react';
import { type PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { providersApi } from '@/shared/services/ai';
import type { AiProvider, ProvidersFilters } from '@/shared/types/ai';
import { AiProviderCard } from './AiProviderCard';
import { AiProviderFilters } from './AiProviderFilters';
import { CreateProviderModal } from './CreateProviderModal';
import { SetupDefaultProvidersModal } from './SetupDefaultProvidersModal';
import { BulkTestModal } from './BulkTestModal';
import { ProviderDetailModal } from './ProviderDetailModal';
import { EditProviderModal } from './EditProviderModal';

export interface AiProvidersPageProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const AiProvidersPage: React.FC<AiProvidersPageProps> = ({ onActionsReady }) => {
  const [providers, setProviders] = useState<AiProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showSetupModal, setShowSetupModal] = useState(false);
  const [showBulkTestModal, setShowBulkTestModal] = useState(false);
  const [selectedProviderId, setSelectedProviderId] = useState<string | null>(null);
  const [editingProviderId, setEditingProviderId] = useState<string | null>(null);
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 20
  });
  const [filters, setFilters] = useState<ProvidersFilters>({
    page: 1,
    per_page: 20,
    sort: 'priority'
  });

  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();
  const isInitialMount = useRef(true);

  const canCreateProviders = hasPermission('ai.providers.create');
  const canManageProviders = hasPermission('ai.providers.update');
  const canTestCredentials = hasPermission('ai.providers.test');

  const loadProviders = useCallback(async (showSpinner = true) => {
    try {
      if (showSpinner) setLoading(true);
      else setRefreshing(true);

      const response = await providersApi.getProviders({
        ...filters,
        search: searchQuery || undefined
      });

      // BaseApiService returns PaginatedResponse<AiProvider>
      const { items, pagination: paginationData } = response;

      if (items && Array.isArray(items)) {
        setProviders(items);
      } else {
        setProviders([]);
      }

      if (paginationData) {
        setPagination(paginationData);
      } else {
        setPagination({
          current_page: 1,
          total_pages: 1,
          total_count: 0,
          per_page: 20
        });
      }
    } catch {
      setProviders([]); // Ensure providers is always an array
      setPagination({ // Ensure pagination is always an object
        current_page: 1,
        total_pages: 1,
        total_count: 0,
        per_page: 20
      });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load AI providers. Please try again.'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [filters, searchQuery, addNotification]);

  const handleSearch = useCallback((query: string) => {
    setSearchQuery(query);
    setFilters(prev => ({ ...prev, page: 1 }));
  }, []);

  const handleFilterChange = useCallback((filters: Partial<ProvidersFilters>) => {
    setFilters(prev => ({ ...prev, ...filters, page: 1 }));
  }, []);

  const handlePageChange = useCallback((page: number) => {
    setFilters(prev => ({ ...prev, page }));
  }, []);

  const handleRefresh = useCallback(() => {
    loadProviders(false);
  }, []);  

  const handleSetupDefaults = useCallback(async (providerTypes?: string[]) => {
    try {
      const types = providerTypes || ['openai', 'anthropic', 'google', 'groq', 'mistral'];
      const result = await providersApi.setupDefaultProviders(types);

      if (result.created_providers && result.created_providers.length > 0) {
        addNotification({
          type: 'success',
          title: 'Providers Created',
          message: `Successfully created ${result.created_providers.length} default provider(s).`
        });
        loadProviders(false);
      } else {
        addNotification({
          type: 'info',
          title: 'No Providers Created',
          message: 'All selected providers already exist in your account.'
        });
      }
    } catch {
      addNotification({
        type: 'error',
        title: 'Setup Failed',
        message: error instanceof Error ? error.message : 'Failed to setup default providers'
      });
    }
    setShowSetupModal(false);
  }, [addNotification]);  

  const handleBulkTest = useCallback(async () => {
    try {
      const response = await providersApi.testAllProviders();
      const { summary } = response;

      if (summary.failed === 0) {
        addNotification({
          type: 'success',
          title: 'All Tests Passed',
          message: `Successfully tested ${summary.successful} provider(s). All connections are healthy.`
        });
      } else if (summary.successful === 0) {
        addNotification({
          type: 'error',
          title: 'All Tests Failed',
          message: `All ${summary.failed} provider test(s) failed. Please check your configurations.`
        });
      } else {
        addNotification({
          type: 'warning',
          title: 'Mixed Results',
          message: `${summary.successful} provider(s) passed, ${summary.failed} provider(s) failed.`
        });
      }

      // Refresh providers to update health status
      loadProviders(false);
    } catch {
      addNotification({
        type: 'error',
        title: 'Bulk Test Failed',
        message: error instanceof Error ? error.message : 'Failed to test providers'
      });
    }
    setShowBulkTestModal(false);
  }, [addNotification]);  

  const handleProviderUpdate = useCallback(() => {
    loadProviders(false);
  }, [loadProviders]);

  // Handle view provider details
  const handleViewProvider = useCallback((providerId: string) => {
    setSelectedProviderId(providerId);
  }, []);

  // Handle delete provider
  const handleDeleteProvider = useCallback(async (providerId: string) => {
    try {
      await providersApi.deleteProvider(providerId);
      addNotification({
        type: 'success',
        title: 'Provider Deleted',
        message: 'Provider has been successfully deleted.'
      });
      setSelectedProviderId(null); // Close detail modal
      loadProviders(false);
    } catch {
      addNotification({
        type: 'error',
        title: 'Delete Failed',
        message: error instanceof Error ? error.message : 'Failed to delete provider'
      });
    }
  }, [addNotification, loadProviders]);

  const getPriorityProviders = () => {
    return providers.filter(p => p.priority_order <= 3);
  };

  const getHealthyProviders = () => {
    return providers.filter(p => p.health_status === 'healthy').length;
  };

  // Load providers on mount and when filters or search query change
   
  useEffect(() => {
    if (isInitialMount.current) {
      // On initial mount, load data once
      isInitialMount.current = false;
      loadProviders();
    } else {
      // On subsequent changes to filters/search, reload data
      loadProviders();
    }
  }, [filters, searchQuery]);

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'outline' as const,
      icon: RefreshCw,
      disabled: refreshing,
      size: 'sm'
    },
    ...(canTestCredentials ? [{
      id: 'test-all',
      label: 'Test All',
      onClick: () => setShowBulkTestModal(true),
      variant: 'outline' as const,
      size: 'sm' as const
    }] : []),
    ...(canCreateProviders ? [
      {
        id: 'setup-defaults',
        label: 'Setup Defaults',
        onClick: () => setShowSetupModal(true),
        variant: 'outline' as const,
        size: 'sm' as const
      },
      {
        id: 'add-provider',
        label: 'Add Provider',
        onClick: () => setShowCreateModal(true),
        variant: 'primary' as const,
        size: 'sm' as const
      }
    ] : [])
  ];

  // Notify parent of actions
  useEffect(() => {
    if (onActionsReady) {
      onActionsReady(pageActions);
    }
  }, [refreshing, canTestCredentials, canCreateProviders]);  

  if (loading) {
    return <LoadingSpinner className="py-12" />;
  }

  return (
    <>
      {/* Summary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Total Providers</p>
              <p className="text-2xl font-semibold text-theme-primary">{pagination?.total_count || 0}</p>
            </div>
            <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
              <Settings className="h-5 w-5 text-theme-info" />
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Healthy Providers</p>
              <p className="text-2xl font-semibold text-theme-primary">{getHealthyProviders()}</p>
            </div>
            <div className="h-10 w-10 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
              <Zap className="h-5 w-5 text-theme-success" />
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Priority Providers</p>
              <p className="text-2xl font-semibold text-theme-primary">{getPriorityProviders().length}</p>
            </div>
            <div className="h-10 w-10 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
              <AlertCircle className="h-5 w-5 text-theme-warning" />
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Active Credentials</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {providers.reduce((sum, p) => sum + (p.credential_count || 0), 0)}
              </p>
            </div>
            <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
              <Settings className="h-5 w-5 text-theme-info" />
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
              placeholder="Search providers..."
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
          <AiProviderFilters
            filters={filters}
            onFiltersChange={handleFilterChange}
          />
        )}
      </div>

      {/* Providers Grid */}
      {providers.length === 0 ? (
        <EmptyState
          icon={Settings}
          title="No AI providers found"
          description="Get started by adding your first AI provider or setting up defaults"
          action={
            canCreateProviders ? (
              <div className="flex gap-2">
                <Button onClick={() => setShowSetupModal(true)} variant="outline">
                  Setup Defaults
                </Button>
                <Button onClick={() => setShowCreateModal(true)}>
                  Add Provider
                </Button>
              </div>
            ) : undefined
          }
        />
      ) : (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {providers.map((provider) => (
              <AiProviderCard
                key={provider.id}
                provider={provider}
                onUpdate={handleProviderUpdate}
                canManage={canManageProviders}
                onViewDetails={handleViewProvider}
                onEditProvider={(providerId) => setEditingProviderId(providerId)}
              />
            ))}
          </div>

          {/* Pagination */}
          {(pagination?.total_pages || 0) > 1 && (
            <div className="mt-8 flex items-center justify-between">
              <div className="text-sm text-theme-tertiary">
                Showing {(((pagination?.current_page || 1) - 1) * (pagination?.per_page || 20)) + 1} to{' '}
                {Math.min((pagination?.current_page || 1) * (pagination?.per_page || 20), pagination?.total_count || 0)} of{' '}
                {pagination?.total_count || 0} providers
              </div>
              
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  disabled={(pagination?.current_page || 1) === 1}
                  onClick={() => handlePageChange((pagination?.current_page || 1) - 1)}
                >
                  Previous
                </Button>
                
                {Array.from({ length: pagination?.total_pages || 1 }, (_, i) => i + 1)
                  .filter(page => 
                    page === 1 || 
                    page === (pagination?.total_pages || 1) || 
                    Math.abs(page - (pagination?.current_page || 1)) <= 2
                  )
                  .map((page, index, array) => (
                    <React.Fragment key={page}>
                      {index > 0 && array[index - 1] !== page - 1 && (
                        <span className="px-2 py-1 text-theme-tertiary">...</span>
                      )}
                      <Button
                        variant={page === (pagination?.current_page || 1) ? 'primary' : 'outline'}
                        size="sm"
                        onClick={() => handlePageChange(page)}
                      >
                        {page}
                      </Button>
                    </React.Fragment>
                  ))
                }
                
                <Button
                  variant="outline"
                  size="sm"
                  disabled={(pagination?.current_page || 1) === (pagination?.total_pages || 1)}
                  onClick={() => handlePageChange((pagination?.current_page || 1) + 1)}
                >
                  Next
                </Button>
              </div>
            </div>
          )}
        </>
      )}

      {/* Modals */}
      {showCreateModal && (
        <CreateProviderModal
          isOpen={showCreateModal}
          onClose={() => setShowCreateModal(false)}
          onSuccess={handleProviderUpdate}
        />
      )}

      {showSetupModal && (
        <SetupDefaultProvidersModal
          isOpen={showSetupModal}
          onClose={() => setShowSetupModal(false)}
          onConfirm={handleSetupDefaults}
        />
      )}

      {showBulkTestModal && (
        <BulkTestModal
          isOpen={showBulkTestModal}
          onClose={() => setShowBulkTestModal(false)}
          onConfirm={handleBulkTest}
        />
      )}

      {/* Provider Detail Modal - Always rendered, visibility controlled by isOpen */}
      <ProviderDetailModal
        isOpen={!!selectedProviderId}
        onClose={() => setSelectedProviderId(null)}
        providerId={selectedProviderId || ''}
        onUpdate={handleProviderUpdate}
        onEdit={(_providerId) => {
          setSelectedProviderId(null); // Close detail modal
          setEditingProviderId(_providerId); // Open edit modal
        }}
        onDelete={handleDeleteProvider}
      />

      {/* Edit Provider Modal - Always rendered, visibility controlled by isOpen */}
      <EditProviderModal
        isOpen={!!editingProviderId}
        onClose={() => setEditingProviderId(null)}
        providerId={editingProviderId || ''}
        onSuccess={handleProviderUpdate}
      />
    </>
  );
};