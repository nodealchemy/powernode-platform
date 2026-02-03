import { useState, useEffect, useCallback, useRef } from 'react';
import { devopsPipelinesApi } from '@/services/devopsPipelinesApi';
import type { DevopsPipeline, DevopsPipelineFormData } from '@/types/devops-pipelines';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface UsePipelinesParams {
  is_active?: boolean;
}

export function usePipelines(params: UsePipelinesParams = {}) {
  const [pipelines, setPipelines] = useState<DevopsPipeline[]>([]);
  const [meta, setMeta] = useState<{
    total: number;
    active_count: number;
    total_runs: number;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef(false);
  const currentParamsRef = useRef<string>('');

  const fetchPipelines = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await devopsPipelinesApi.getAll(params);
      setPipelines(data.pipelines);
      setMeta(data.meta);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch pipelines';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [params]);

  useEffect(() => {
    const paramsKey = JSON.stringify(params);
    if (!hasLoadedRef.current || currentParamsRef.current !== paramsKey) {
      hasLoadedRef.current = true;
      currentParamsRef.current = paramsKey;
      fetchPipelines();
    }
     
  }, [params.is_active]);

  const createPipeline = async (data: DevopsPipelineFormData) => {
    try {
      const pipeline = await devopsPipelinesApi.create(data);
      showNotification('Pipeline created successfully', 'success');
      await fetchPipelines();
      return pipeline;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to create pipeline';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  const updatePipeline = async (id: string, data: Partial<DevopsPipelineFormData>) => {
    try {
      const pipeline = await devopsPipelinesApi.update(id, data);
      showNotification('Pipeline updated successfully', 'success');
      await fetchPipelines();
      return pipeline;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to update pipeline';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  const deletePipeline = async (id: string) => {
    try {
      await devopsPipelinesApi.delete(id);
      showNotification('Pipeline deleted successfully', 'success');
      await fetchPipelines();
      return true;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to delete pipeline';
      showNotification(errorMessage, 'error');
      return false;
    }
  };

  const triggerPipeline = async (id: string, context?: Record<string, unknown>) => {
    try {
      const run = await devopsPipelinesApi.trigger(id, context);
      showNotification('Pipeline triggered successfully', 'success');
      return run;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to trigger pipeline';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  const duplicatePipeline = async (id: string) => {
    try {
      const pipeline = await devopsPipelinesApi.duplicate(id);
      showNotification('Pipeline duplicated successfully', 'success');
      await fetchPipelines();
      return pipeline;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to duplicate pipeline';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  const exportPipelineYaml = async (id: string) => {
    try {
      const result = await devopsPipelinesApi.exportYaml(id);
      return result;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to export pipeline YAML';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  return {
    pipelines,
    meta,
    loading,
    error,
    refresh: fetchPipelines,
    createPipeline,
    updatePipeline,
    deletePipeline,
    triggerPipeline,
    duplicatePipeline,
    exportPipelineYaml,
  };
}

export function usePipeline(id: string | null) {
  const [pipeline, setPipeline] = useState<DevopsPipeline | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef<string | null>(null);

  const fetchPipeline = useCallback(async () => {
    if (!id) return;

    try {
      setLoading(true);
      setError(null);
      // Pass true to include recent runs in the response
      const data = await devopsPipelinesApi.getById(id, true);
      setPipeline(data);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch pipeline';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (id && hasLoadedRef.current !== id) {
      hasLoadedRef.current = id;
      fetchPipeline();
    }
     
  }, [id]);

  const updatePipeline = async (data: Partial<DevopsPipelineFormData>) => {
    if (!id) return null;

    try {
      const updated = await devopsPipelinesApi.update(id, data);
      showNotification('Pipeline updated successfully', 'success');
      setPipeline(updated);
      return updated;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to update pipeline';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  return {
    pipeline,
    loading,
    error,
    refresh: fetchPipeline,
    updatePipeline,
  };
}
