import { useState, useEffect, useCallback } from 'react';
import { integrationsApi } from '../services/integrationsApi';
import type {
  IntegrationInstanceSummary,
  IntegrationTemplateSummary,
  IntegrationInstance,
  IntegrationTemplate,
  InstanceFilters,
  TemplateFilters,
  Pagination,
} from '../types';

interface UseIntegrationsOptions {
  filters?: InstanceFilters;
  autoLoad?: boolean;
}

interface UseIntegrationsResult {
  instances: IntegrationInstanceSummary[];
  pagination: Pagination | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  loadMore: () => Promise<void>;
}

export function useIntegrations(options: UseIntegrationsOptions = {}): UseIntegrationsResult {
  const { filters, autoLoad = true } = options;
  const [instances, setInstances] = useState<IntegrationInstanceSummary[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);

  const fetchInstances = useCallback(
    async (pageNum: number, append = false) => {
      setIsLoading(true);
      setError(null);

      const response = await integrationsApi.getInstances(pageNum, 20, filters);

      if (response.success && response.data) {
        if (append) {
          setInstances((prev) => [...prev, ...response.data!.instances]);
        } else {
          setInstances(response.data.instances);
        }
        setPagination(response.data.pagination);
      } else {
        setError(response.error || 'Failed to fetch integrations');
      }

      setIsLoading(false);
    },
    [filters]
  );

  useEffect(() => {
    if (autoLoad) {
      setPage(1);
      fetchInstances(1);
    }
  }, [fetchInstances, autoLoad]);

  const refetch = useCallback(async () => {
    setPage(1);
    await fetchInstances(1);
  }, [fetchInstances]);

  const loadMore = useCallback(async () => {
    if (pagination && page < pagination.total_pages) {
      const nextPage = page + 1;
      setPage(nextPage);
      await fetchInstances(nextPage, true);
    }
  }, [pagination, page, fetchInstances]);

  return {
    instances,
    pagination,
    isLoading,
    error,
    refetch,
    loadMore,
  };
}

interface UseIntegrationOptions {
  id: string;
  autoLoad?: boolean;
}

interface UseIntegrationResult {
  instance: IntegrationInstance | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useIntegration(options: UseIntegrationOptions): UseIntegrationResult {
  const { id, autoLoad = true } = options;
  const [instance, setInstance] = useState<IntegrationInstance | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchInstance = useCallback(async () => {
    if (!id) return;

    setIsLoading(true);
    setError(null);

    const response = await integrationsApi.getInstance(id);

    if (response.success && response.data) {
      setInstance(response.data.instance);
    } else {
      setError(response.error || 'Failed to fetch integration');
    }

    setIsLoading(false);
  }, [id]);

  useEffect(() => {
    if (autoLoad) {
      fetchInstance();
    }
  }, [fetchInstance, autoLoad]);

  return {
    instance,
    isLoading,
    error,
    refetch: fetchInstance,
  };
}

interface UseTemplatesOptions {
  filters?: TemplateFilters;
  autoLoad?: boolean;
}

interface UseTemplatesResult {
  templates: IntegrationTemplateSummary[];
  pagination: Pagination | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  search: (query: string) => Promise<void>;
}

export function useTemplates(options: UseTemplatesOptions = {}): UseTemplatesResult {
  const { filters, autoLoad = true } = options;
  const [templates, setTemplates] = useState<IntegrationTemplateSummary[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchTemplates = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    const response = await integrationsApi.getTemplates(1, 100, filters);

    if (response.success && response.data) {
      setTemplates(response.data.templates);
      setPagination(response.data.pagination);
    } else {
      setError(response.error || 'Failed to fetch templates');
    }

    setIsLoading(false);
  }, [filters]);

  useEffect(() => {
    if (autoLoad) {
      fetchTemplates();
    }
  }, [fetchTemplates, autoLoad]);

  const search = useCallback(async (query: string) => {
    setIsLoading(true);
    setError(null);

    const response = await integrationsApi.searchTemplates(query);

    if (response.success && response.data) {
      setTemplates(response.data.templates);
      setPagination(response.data.pagination);
    } else {
      setError(response.error || 'Failed to search templates');
    }

    setIsLoading(false);
  }, []);

  return {
    templates,
    pagination,
    isLoading,
    error,
    refetch: fetchTemplates,
    search,
  };
}

interface UseTemplateOptions {
  id: string;
  autoLoad?: boolean;
}

interface UseTemplateResult {
  template: IntegrationTemplate | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useTemplate(options: UseTemplateOptions): UseTemplateResult {
  const { id, autoLoad = true } = options;
  const [template, setTemplate] = useState<IntegrationTemplate | null>(null);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchTemplate = useCallback(async () => {
    if (!id) return;

    setIsLoading(true);
    setError(null);

    const response = await integrationsApi.getTemplate(id);

    if (response.success && response.data) {
      setTemplate(response.data.template);
    } else {
      setError(response.error || 'Failed to fetch template');
    }

    setIsLoading(false);
  }, [id]);

  useEffect(() => {
    if (autoLoad) {
      fetchTemplate();
    }
  }, [fetchTemplate, autoLoad]);

  return {
    template,
    isLoading,
    error,
    refetch: fetchTemplate,
  };
}
