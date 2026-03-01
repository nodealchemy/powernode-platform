import React, { useEffect, useState } from 'react';
import { ArrowLeft } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useExecutionResources } from '@/features/ai/execution-resources/hooks/useExecutionResources';
import { ResourceListPanel } from '@/features/ai/execution-resources/components/ResourceListPanel';
import { ResourceDetailPanel } from '@/features/ai/execution-resources/components/ResourceDetailPanel';

interface ExecutionResourcesContentProps {
  refreshKey?: number;
}

export const ExecutionResourcesContent: React.FC<ExecutionResourcesContentProps> = ({ refreshKey: externalRefreshKey }) => {
  const {
    resources,
    counts,
    loading,
    error,
    filters,
    pagination,
    selectedResource,
    detailResource,
    detailLoading,
    setFilters,
    setPage,
    selectResource,
    refreshResources,
  } = useExecutionResources();

  const [mobileShowDetail, setMobileShowDetail] = useState(false);

  useEffect(() => {
    if (externalRefreshKey && externalRefreshKey > 0) {
      refreshResources();
    }
  }, [externalRefreshKey, refreshResources]);

  const handleSelectResource = (resource: import('@/features/ai/execution-resources/types').ExecutionResource) => {
    selectResource(resource);
    setMobileShowDetail(true);
  };

  const handleMobileBack = () => {
    setMobileShowDetail(false);
    selectResource(null);
  };

  return (
    <div className="flex flex-col h-[calc(100vh-280px)]">
      {error && (
        <div className="p-3 mb-2 rounded-lg bg-theme-danger/10 text-theme-danger text-sm flex-shrink-0">
          {error}
        </div>
      )}

      {/* Desktop: side-by-side */}
      <div className="hidden lg:flex flex-1 min-h-0 rounded-lg border border-theme overflow-hidden">
        <ResourceListPanel
          resources={resources}
          counts={counts}
          loading={loading}
          selectedResourceId={selectedResource?.id ?? null}
          onSelectResource={handleSelectResource}
          pagination={pagination}
          onPageChange={setPage}
          filters={filters}
          onFilterChange={setFilters}
        />
        <ResourceDetailPanel
          resource={selectedResource}
          detailResource={detailResource}
          detailLoading={detailLoading}
        />
      </div>

      {/* Mobile: list or detail */}
      <div className="flex lg:hidden flex-1 min-h-0 rounded-lg border border-theme overflow-hidden">
        {mobileShowDetail && selectedResource ? (
          <div className="flex-1 flex flex-col">
            <button
              onClick={handleMobileBack}
              className="flex items-center gap-1.5 px-3 py-2 text-sm text-theme-secondary hover:text-theme-primary border-b border-theme"
            >
              <ArrowLeft className="w-4 h-4" />
              Back to list
            </button>
            <ResourceDetailPanel
              resource={selectedResource}
              detailResource={detailResource}
              detailLoading={detailLoading}
            />
          </div>
        ) : (
          <ResourceListPanel
            resources={resources}
            counts={counts}
            loading={loading}
            selectedResourceId={selectedResource?.id ?? null}
            onSelectResource={handleSelectResource}
            pagination={pagination}
            onPageChange={setPage}
            filters={filters}
            onFilterChange={setFilters}
          />
        )}
      </div>
    </div>
  );
};

export default function ExecutionResourcesPage() {
  return (
    <PageContainer
      title="Execution Resources"
      description="Browse artifacts, branches, memory, and other execution-produced resources"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Execution Resources' },
      ]}
    >
      <ExecutionResourcesContent />
    </PageContainer>
  );
}
