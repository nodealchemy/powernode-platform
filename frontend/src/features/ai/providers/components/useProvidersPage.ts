import { useState, useEffect, useCallback, useRef } from 'react';
import { RefreshCw } from 'lucide-react';
import { type PageAction } from '@/shared/components/layout/PageContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { providersApi } from '@/shared/services/ai';
import type { AiProvider, ProvidersFilters } from '@/shared/types/ai';

export function useProvidersPage() {
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
    } catch (_error) {
      setProviders([]);
      setPagination({
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

  const handleFilterChange = useCallback((newFilters: Partial<ProvidersFilters>) => {
    setFilters(prev => ({ ...prev, ...newFilters, page: 1 }));
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
    } catch (error) {
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

      loadProviders(false);
    } catch (error) {
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

  const handleViewProvider = useCallback((providerId: string) => {
    setSelectedProviderId(providerId);
  }, []);

  const handleDeleteProvider = useCallback(async (providerId: string) => {
    try {
      await providersApi.deleteProvider(providerId);
      addNotification({
        type: 'success',
        title: 'Provider Deleted',
        message: 'Provider has been successfully deleted.'
      });
      setSelectedProviderId(null);
      loadProviders(false);
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Delete Failed',
        message: error instanceof Error ? error.message : 'Failed to delete provider'
      });
    }
  }, [addNotification, loadProviders]);

  const getPriorityProviders = useCallback(() => {
    return providers.filter(p => p.priority_order <= 3);
  }, [providers]);

  const getHealthyProviders = useCallback(() => {
    return providers.filter(p => p.health_status === 'healthy').length;
  }, [providers]);

  useEffect(() => {
    if (isInitialMount.current) {
      isInitialMount.current = false;
      loadProviders();
    } else {
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

  return {
    providers,
    loading,
    refreshing,
    searchQuery,
    showFilters,
    showCreateModal,
    showSetupModal,
    showBulkTestModal,
    selectedProviderId,
    editingProviderId,
    pagination,
    filters,
    canCreateProviders,
    canManageProviders,
    canTestCredentials,
    pageActions,
    setShowFilters,
    setShowCreateModal,
    setShowSetupModal,
    setShowBulkTestModal,
    setSelectedProviderId,
    setEditingProviderId,
    handleSearch,
    handleFilterChange,
    handlePageChange,
    handleRefresh,
    handleSetupDefaults,
    handleBulkTest,
    handleProviderUpdate,
    handleViewProvider,
    handleDeleteProvider,
    getPriorityProviders,
    getHealthyProviders,
  };
}
