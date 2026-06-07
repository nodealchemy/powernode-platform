import React, { useEffect } from 'react';
import { Search, Filter, Database } from 'lucide-react';
import { type PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { DataSourceStatsCards } from './DataSourceStatsCards';
import { DataSourceCard } from './DataSourceCard';
import { DataSourceDiscoveryPanel } from './DataSourceDiscoveryPanel';
import { DataSourceFilters } from './DataSourceFilters';
import { CreateDataSourceModal } from './CreateDataSourceModal';
import { DataSourceDetailModal } from './DataSourceDetailModal';
import { EditDataSourceModal } from './EditDataSourceModal';
import { useDataSourcesPage } from './useDataSourcesPage';

export interface AiDataSourcesPageProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const AiDataSourcesPage: React.FC<AiDataSourcesPageProps> = ({ onActionsReady }) => {
  const {
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
    pageActions,
    setShowFilters,
    setShowCreateModal,
    setSelectedDataSourceId,
    setEditingDataSourceId,
    handleSearch,
    handleFilterChange,
    handlePageChange,
    handleDataSourceUpdate,
    handleViewDataSource,
    handleDeleteDataSource,
    getHealthyCount,
    getRequiresAuthCount,
  } = useDataSourcesPage();

  useEffect(() => {
    if (onActionsReady) {
      onActionsReady(pageActions);
    }
  }, [refreshing, canCreateDataSources]);

  if (loading) {
    return <LoadingSpinner className="py-12" />;
  }

  return (
    <>
      <DataSourceStatsCards
        totalCount={pagination?.total_count || 0}
        healthyCount={getHealthyCount()}
        requiresAuthCount={getRequiresAuthCount()}
        credentialCount={dataSources.reduce((sum, ds) => sum + (ds.credential_count || 0), 0)}
      />

      <DataSourceDiscoveryPanel onSelectDataSource={handleViewDataSource} />

      <div className="mb-6">
        <div className="flex items-center gap-4 mb-4">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
            <Input
              placeholder="Search data sources..."
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
          <DataSourceFilters
            filters={filters}
            onFiltersChange={handleFilterChange}
          />
        )}
      </div>

      {dataSources.length === 0 ? (
        <EmptyState
          icon={Database}
          title="No data sources found"
          description="Get started by adding your first data source"
          action={
            canCreateDataSources ? (
              <Button onClick={() => setShowCreateModal(true)}>
                Add Data Source
              </Button>
            ) : undefined
          }
        />
      ) : (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {dataSources.map((dataSource) => (
              <DataSourceCard
                key={dataSource.id}
                dataSource={dataSource}
                onUpdate={handleDataSourceUpdate}
                canManage={canManageDataSources}
                onViewDetails={handleViewDataSource}
                onEditDataSource={(dsId) => setEditingDataSourceId(dsId)}
              />
            ))}
          </div>

          {(pagination?.total_pages || 0) > 1 && (
            <div className="mt-8 flex items-center justify-between">
              <div className="text-sm text-theme-tertiary">
                Showing {(((pagination?.current_page || 1) - 1) * (pagination?.per_page || 20)) + 1} to{' '}
                {Math.min((pagination?.current_page || 1) * (pagination?.per_page || 20), pagination?.total_count || 0)} of{' '}
                {pagination?.total_count || 0} data sources
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

      {showCreateModal && (
        <CreateDataSourceModal
          isOpen={showCreateModal}
          onClose={() => setShowCreateModal(false)}
          onSuccess={handleDataSourceUpdate}
        />
      )}

      <DataSourceDetailModal
        isOpen={!!selectedDataSourceId}
        onClose={() => setSelectedDataSourceId(null)}
        dataSourceId={selectedDataSourceId || ''}
        onUpdate={handleDataSourceUpdate}
        onEdit={(dsId) => {
          setSelectedDataSourceId(null);
          setEditingDataSourceId(dsId);
        }}
        onDelete={handleDeleteDataSource}
      />

      <EditDataSourceModal
        isOpen={!!editingDataSourceId}
        onClose={() => setEditingDataSourceId(null)}
        dataSourceId={editingDataSourceId || ''}
        onSuccess={handleDataSourceUpdate}
      />
    </>
  );
};
