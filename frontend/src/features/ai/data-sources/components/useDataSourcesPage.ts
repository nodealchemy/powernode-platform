import { useState, useEffect, useCallback, useRef } from 'react';
import { RefreshCw } from 'lucide-react';
import { type PageAction } from '@/shared/components/layout/PageContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import type { AiDataSource, DataSourceFilters } from '@/shared/types/ai';

export function useDataSourcesPage() {
  const [dataSources, setDataSources] = useState<AiDataSource[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [selectedDataSourceId, setSelectedDataSourceId] = useState<string | null>(null);
  const [editingDataSourceId, setEditingDataSourceId] = useState<string | null>(null);
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 20
  });
  const [filters, setFilters] = useState<DataSourceFilters>({
    page: 1,
    per_page: 20,
    sort: 'priority'
  });

  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();
  const isInitialMount = useRef(true);

  const canCreateDataSources = hasPermission('ai.data_sources.create');
  const canManageDataSources = hasPermission('ai.data_sources.update');
  const canDeleteDataSources = hasPermission('ai.data_sources.delete');

  const loadDataSources = useCallback(async (showSpinner = true) => {
    try {
      if (showSpinner) setLoading(true);
      else setRefreshing(true);

      const response = await dataSourcesApi.getDataSources({
        ...filters,
        search: searchQuery || undefined
      });

      const { items, pagination: paginationData } = response;

      if (items && Array.isArray(items)) {
        setDataSources(items);
      } else {
        setDataSources([]);
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
      setDataSources([]);
      setPagination({
        current_page: 1,
        total_pages: 1,
        total_count: 0,
        per_page: 20
      });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load data sources. Please try again.'
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

  const handleFilterChange = useCallback((newFilters: Partial<DataSourceFilters>) => {
    setFilters(prev => ({ ...prev, ...newFilters, page: 1 }));
  }, []);

  const handlePageChange = useCallback((page: number) => {
    setFilters(prev => ({ ...prev, page }));
  }, []);

  const handleRefresh = useCallback(() => {
    loadDataSources(false);
  }, []);

  const handleDataSourceUpdate = useCallback(() => {
    loadDataSources(false);
  }, [loadDataSources]);

  const handleViewDataSource = useCallback((dataSourceId: string) => {
    setSelectedDataSourceId(dataSourceId);
  }, []);

  const handleDeleteDataSource = useCallback(async (dataSourceId: string) => {
    try {
      await dataSourcesApi.deleteDataSource(dataSourceId);
      addNotification({
        type: 'success',
        title: 'Data Source Deleted',
        message: 'Data source has been successfully deleted.'
      });
      setSelectedDataSourceId(null);
      loadDataSources(false);
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Delete Failed',
        message: error instanceof Error ? error.message : 'Failed to delete data source'
      });
    }
  }, [addNotification, loadDataSources]);

  const getHealthyCount = useCallback(() => {
    return dataSources.filter(ds => ds.health_status === 'healthy').length;
  }, [dataSources]);

  const getRequiresAuthCount = useCallback(() => {
    return dataSources.filter(ds => ds.requires_auth).length;
  }, [dataSources]);

  useEffect(() => {
    if (isInitialMount.current) {
      isInitialMount.current = false;
      loadDataSources();
    } else {
      loadDataSources();
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
    ...(canCreateDataSources ? [
      {
        id: 'add-data-source',
        label: 'Add Data Source',
        onClick: () => setShowCreateModal(true),
        variant: 'primary' as const,
        size: 'sm' as const
      }
    ] : [])
  ];

  return {
    dataSources,
    loading,
    refreshing,
    searchQuery,
    showFilters,
    showCreateModal,
    selectedDataSourceId,
    editingDataSourceId,
    pagination,
    filters,
    canCreateDataSources,
    canManageDataSources,
    canDeleteDataSources,
    pageActions,
    setShowFilters,
    setShowCreateModal,
    setSelectedDataSourceId,
    setEditingDataSourceId,
    handleSearch,
    handleFilterChange,
    handlePageChange,
    handleRefresh,
    handleDataSourceUpdate,
    handleViewDataSource,
    handleDeleteDataSource,
    getHealthyCount,
    getRequiresAuthCount,
  };
}
