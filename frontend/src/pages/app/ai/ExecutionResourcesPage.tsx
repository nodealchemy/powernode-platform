import React, { useState, useEffect } from 'react';
import { LayoutGrid, List, RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useExecutionResources } from '@/features/ai/execution-resources/hooks/useExecutionResources';
import { ResourceStatsBar } from '@/features/ai/execution-resources/components/ResourceStatsBar';
import { ResourceFilterBar } from '@/features/ai/execution-resources/components/ResourceFilterBar';
import { ResourceCard } from '@/features/ai/execution-resources/components/ResourceCard';
import { ResourceList } from '@/features/ai/execution-resources/components/ResourceList';
import { ResourceDetailDrawer } from '@/features/ai/execution-resources/components/ResourceDetailDrawer';
import type { ResourceType } from '@/features/ai/execution-resources/types';

interface ExecutionResourcesContentProps {
  refreshKey?: number;
}

export const ExecutionResourcesContent: React.FC<ExecutionResourcesContentProps> = ({ refreshKey: externalRefreshKey }) => {
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');
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
    clearFilters,
    setPage,
    selectResource,
    refreshResources,
  } = useExecutionResources();

  useEffect(() => {
    if (externalRefreshKey && externalRefreshKey > 0) {
      refreshResources();
    }
  }, [externalRefreshKey, refreshResources]);

  const handleTypeClick = (type: ResourceType | undefined) => {
    setFilters({ type });
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Execution Resources</h1>
          <p className="text-sm text-theme-secondary mt-1">
            Browse artifacts, branches, memory, and other execution-produced resources
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={refreshResources}
            className="p-2 rounded-lg hover:bg-theme-surface-hover transition-colors text-theme-secondary"
            title="Refresh"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
          <div className="flex rounded-lg border border-theme overflow-hidden">
            <button
              onClick={() => setViewMode('grid')}
              className={`p-2 ${viewMode === 'grid' ? 'bg-theme-surface-selected text-theme-primary' : 'text-theme-tertiary hover:bg-theme-surface-hover'}`}
            >
              <LayoutGrid className="w-4 h-4" />
            </button>
            <button
              onClick={() => setViewMode('list')}
              className={`p-2 ${viewMode === 'list' ? 'bg-theme-surface-selected text-theme-primary' : 'text-theme-tertiary hover:bg-theme-surface-hover'}`}
            >
              <List className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      <ResourceStatsBar
        counts={counts}
        activeType={filters.type}
        onTypeClick={handleTypeClick}
      />

      <ResourceFilterBar
        filters={filters}
        onFilterChange={setFilters}
        onClear={clearFilters}
      />

      {error && (
        <div className="p-4 rounded-lg bg-theme-danger/10 text-theme-danger text-sm">
          {error}
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center py-12">
          <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
        </div>
      ) : viewMode === 'grid' ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {resources.map((resource, idx) => (
            <ResourceCard
              key={`${resource.resource_type}-${resource.id}-${idx}`}
              resource={resource}
              onClick={selectResource}
            />
          ))}
          {resources.length === 0 && (
            <div className="col-span-full text-center py-12 text-theme-tertiary">
              No resources found
            </div>
          )}
        </div>
      ) : (
        <ResourceList resources={resources} onResourceClick={selectResource} />
      )}

      {pagination.total_pages > 1 && (
        <div className="flex items-center justify-center gap-2 pt-4">
          <button
            onClick={() => setPage(pagination.current_page - 1)}
            disabled={pagination.current_page <= 1}
            className="px-3 py-1.5 text-sm rounded-lg border border-theme text-theme-secondary hover:bg-theme-surface-hover disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Previous
          </button>
          <span className="text-sm text-theme-secondary">
            Page {pagination.current_page} of {pagination.total_pages}
          </span>
          <button
            onClick={() => setPage(pagination.current_page + 1)}
            disabled={pagination.current_page >= pagination.total_pages}
            className="px-3 py-1.5 text-sm rounded-lg border border-theme text-theme-secondary hover:bg-theme-surface-hover disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Next
          </button>
        </div>
      )}

      <ResourceDetailDrawer resource={selectedResource} detailResource={detailResource} detailLoading={detailLoading} onClose={() => selectResource(null)} />
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
