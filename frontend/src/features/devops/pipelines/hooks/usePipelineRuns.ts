import { useState, useEffect, useCallback, useRef } from 'react';
import { devopsPipelineRunsApi } from '@/services/devopsPipelinesApi';
import type { DevopsPipelineRun } from '@/types/devops-pipelines';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useDevopsRunsWebSocket } from './useDevopsWebSocket';

interface UsePipelineRunsParams {
  pipeline_id?: string;
  status?: string;
  trigger_type?: string;
  page?: number;
  per_page?: number;
}

export function usePipelineRuns(params: UsePipelineRunsParams = {}) {
  const [runs, setRuns] = useState<DevopsPipelineRun[]>([]);
  const [meta, setMeta] = useState<{
    total: number;
    page: number;
    per_page: number;
    total_pages: number;
    status_counts: Record<string, number>;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef(false);
  const currentParamsRef = useRef<string>('');

  const fetchRuns = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await devopsPipelineRunsApi.getAll(params);
      setRuns(data.pipeline_runs);
      setMeta(data.meta);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch pipeline runs';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [params]);

  // WebSocket integration for live updates
  useDevopsRunsWebSocket(
    params.pipeline_id,
    // On run created - add to list
    (newRun) => {
      setRuns((prev) => {
        // Check if run already exists
        if (prev.some((r) => r.id === newRun.id)) return prev;
        return [newRun as DevopsPipelineRun, ...prev];
      });
    },
    // On run updated - update in list
    (updatedRun) => {
      setRuns((prev) =>
        prev.map((r) =>
          r.id === updatedRun.id ? { ...r, ...updatedRun } : r
        )
      );
    }
  );

  useEffect(() => {
    const paramsKey = JSON.stringify(params);
    if (!hasLoadedRef.current || currentParamsRef.current !== paramsKey) {
      hasLoadedRef.current = true;
      currentParamsRef.current = paramsKey;
      fetchRuns();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params.pipeline_id, params.status, params.trigger_type, params.page, params.per_page]);

  const cancelRun = async (id: string) => {
    try {
      const run = await devopsPipelineRunsApi.cancel(id);
      showNotification('Pipeline run cancelled', 'success');
      await fetchRuns();
      return run;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to cancel pipeline run';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  const retryRun = async (id: string) => {
    try {
      const run = await devopsPipelineRunsApi.retry(id);
      showNotification('Pipeline run retried', 'success');
      await fetchRuns();
      return run;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to retry pipeline run';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  return {
    runs,
    meta,
    loading,
    error,
    refresh: fetchRuns,
    cancelRun,
    retryRun,
  };
}

export function usePipelineRun(id: string | null) {
  const [run, setRun] = useState<DevopsPipelineRun | null>(null);
  const [logs, setLogs] = useState<Array<{
    step_id: string;
    step_name: string;
    step_type: string;
    status: string;
    started_at: string | null;
    completed_at: string | null;
    duration_seconds: number | null;
    logs: string;
    outputs: Record<string, unknown>;
    error_message: string | null;
  }>>([]);
  const [loading, setLoading] = useState(false);
  const [logsLoading, setLogsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef<string | null>(null);

  const fetchRun = useCallback(async () => {
    if (!id) return;

    try {
      setLoading(true);
      setError(null);
      const data = await devopsPipelineRunsApi.getById(id);
      setRun(data);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch pipeline run';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [id]);

  const fetchLogs = useCallback(async () => {
    if (!id) return;

    try {
      setLogsLoading(true);
      const data = await devopsPipelineRunsApi.getLogs(id);
      setLogs(data.logs);
    } catch (err) {
      // Logs might not be available yet
    } finally {
      setLogsLoading(false);
    }
  }, [id]);

  // Track previous status for log refresh logic
  const prevStatusRef = useRef<string | undefined>(undefined);

  useEffect(() => {
    if (id && hasLoadedRef.current !== id) {
      hasLoadedRef.current = id;
      fetchRun();
      fetchLogs();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  // WebSocket integration for live updates on this specific run
  useDevopsRunsWebSocket(
    undefined, // Subscribe to all account updates
    undefined, // Not needed for single run
    // On run updated - update if it's our run
    (updatedRun) => {
      if (updatedRun.id === id) {
        setRun((prev) => prev ? { ...prev, ...updatedRun } : null);
        // Refresh logs when status changes
        if (updatedRun.status && updatedRun.status !== prevStatusRef.current) {
          prevStatusRef.current = updatedRun.status;
          fetchLogs();
        }
      }
    }
  );

  const cancelRun = async () => {
    if (!id) return null;

    try {
      const updated = await devopsPipelineRunsApi.cancel(id);
      showNotification('Pipeline run cancelled', 'success');
      setRun(updated);
      return updated;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to cancel pipeline run';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  const retryRun = async () => {
    if (!id) return null;

    try {
      const newRun = await devopsPipelineRunsApi.retry(id);
      showNotification('Pipeline run retried', 'success');
      return newRun;
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: string } }; message?: string };
      const errorMessage = axiosError?.response?.data?.error
        || axiosError?.message
        || 'Failed to retry pipeline run';
      showNotification(errorMessage, 'error');
      return null;
    }
  };

  return {
    run,
    logs,
    loading,
    logsLoading,
    error,
    refresh: fetchRun,
    refreshLogs: fetchLogs,
    cancelRun,
    retryRun,
  };
}
