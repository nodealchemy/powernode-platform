import { useState, useEffect, useCallback } from 'react';
import { executionResourcesApi } from '../services/executionResourcesApi';
import type { ExecutionResource, ResourceCounts, ResourceFilters } from '../types';

interface UseExecutionResourcesOptions {
  teamId?: string;
  executionId?: string;
  autoLoad?: boolean;
}

interface PaginationState {
  current_page: number;
  total_pages: number;
  total_count: number;
  per_page: number;
}

export function useExecutionResources(options: UseExecutionResourcesOptions = {}) {
  const [resources, setResources] = useState<ExecutionResource[]>([]);
  const [counts, setCounts] = useState<ResourceCounts>({ total: 0 });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filters, setFiltersState] = useState<ResourceFilters>({
    team_id: options.teamId,
    execution_id: options.executionId,
    page: 1,
    per_page: 25,
  });
  const [pagination, setPagination] = useState<PaginationState>({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 25,
  });
  const [selectedResource, setSelectedResource] = useState<ExecutionResource | null>(null);

  const fetchResources = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [resourcesResult, countsResult] = await Promise.all([
        executionResourcesApi.getResources(filters),
        executionResourcesApi.getResourceCounts(filters),
      ]);

      setResources(resourcesResult.items || []);
      setPagination(resourcesResult.pagination || {
        current_page: 1,
        total_pages: 1,
        total_count: 0,
        per_page: 25,
      });
      setCounts(countsResult.counts || { total: 0 });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to load resources';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [filters]);

  useEffect(() => {
    if (options.autoLoad !== false) {
      fetchResources();
    }
  }, [fetchResources, options.autoLoad]);

  const setFilters = useCallback((newFilters: Partial<ResourceFilters>) => {
    setFiltersState(prev => ({ ...prev, ...newFilters, page: 1 }));
  }, []);

  const clearFilters = useCallback(() => {
    setFiltersState({
      team_id: options.teamId,
      execution_id: options.executionId,
      page: 1,
      per_page: 25,
    });
  }, [options.teamId, options.executionId]);

  const setPage = useCallback((page: number) => {
    setFiltersState(prev => ({ ...prev, page }));
  }, []);

  const selectResource = useCallback((resource: ExecutionResource | null) => {
    setSelectedResource(resource);
  }, []);

  const refreshResources = useCallback(() => {
    fetchResources();
  }, [fetchResources]);

  return {
    resources,
    counts,
    loading,
    error,
    filters,
    pagination,
    selectedResource,
    setFilters,
    clearFilters,
    setPage,
    selectResource,
    refreshResources,
  };
}
