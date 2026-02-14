import React, { useEffect } from 'react';
import { Search, Filter, Settings } from 'lucide-react';
import { type PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { ProviderStatsCards } from './ProviderStatsCards';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { AiProviderCard } from './AiProviderCard';
import { AiProviderFilters } from './AiProviderFilters';
import { CreateProviderModal } from './CreateProviderModal';
import { SetupDefaultProvidersModal } from './SetupDefaultProvidersModal';
import { BulkTestModal } from './BulkTestModal';
import { ProviderDetailModal } from './ProviderDetailModal';
import { EditProviderModal } from './EditProviderModal';
import { useProvidersPage } from './useProvidersPage';

export interface AiProvidersPageProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const AiProvidersPage: React.FC<AiProvidersPageProps> = ({ onActionsReady }) => {
  const {
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
    handleSetupDefaults,
    handleBulkTest,
    handleProviderUpdate,
    handleViewProvider,
    handleDeleteProvider,
    getPriorityProviders,
    getHealthyProviders,
  } = useProvidersPage();

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
      <ProviderStatsCards
        totalCount={pagination?.total_count || 0}
        healthyCount={getHealthyProviders()}
        priorityCount={getPriorityProviders().length}
        credentialCount={providers.reduce((sum, p) => sum + (p.credential_count || 0), 0)}
      />

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

      <ProviderDetailModal
        isOpen={!!selectedProviderId}
        onClose={() => setSelectedProviderId(null)}
        providerId={selectedProviderId || ''}
        onUpdate={handleProviderUpdate}
        onEdit={(_providerId) => {
          setSelectedProviderId(null);
          setEditingProviderId(_providerId);
        }}
        onDelete={handleDeleteProvider}
      />

      <EditProviderModal
        isOpen={!!editingProviderId}
        onClose={() => setEditingProviderId(null)}
        providerId={editingProviderId || ''}
        onSuccess={handleProviderUpdate}
      />
    </>
  );
};
