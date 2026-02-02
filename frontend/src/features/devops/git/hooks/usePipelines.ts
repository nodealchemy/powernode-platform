import { useState, useEffect, useCallback } from 'react';
import { gitProvidersApi } from '../services/gitProvidersApi';
import {
  GitPipeline,
  GitPipelineDetail,
  GitPipelineJob,
  PaginationInfo,
  PipelineStats,
} from '../types';

interface UsePipelinesParams {
  repositoryId: string;
  page?: number;
  perPage?: number;
  status?: string;
  conclusion?: string;
  ref?: string;
}

export function usePipelines(params: UsePipelinesParams) {
  const [pipelines, setPipelines] = useState<GitPipeline[]>([]);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [stats, setStats] = useState<PipelineStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchPipelines = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getPipelines(params.repositoryId, {
        page: params.page,
        per_page: params.perPage,
        status: params.status,
        conclusion: params.conclusion,
        ref: params.ref,
      });
      setPipelines(data.pipelines);
      setPagination(data.pagination);
      setStats(data.stats);
    } catch {
      setError(
        err instanceof Error ? err.message : 'Failed to fetch pipelines'
      );
    } finally {
      setLoading(false);
    }
  }, [
    params.repositoryId,
    params.page,
    params.perPage,
    params.status,
    params.conclusion,
    params.ref,
  ]);

  useEffect(() => {
    fetchPipelines();
  }, [fetchPipelines]);

  const triggerPipeline = useCallback(
    async (options?: {
      ref?: string;
      workflow_id?: string;
      inputs?: Record<string, string>;
    }) => {
      const result = await gitProvidersApi.triggerPipeline(
        params.repositoryId,
        options
      );
      await fetchPipelines();
      return result;
    },
    [params.repositoryId, fetchPipelines]
  );

  const cancelPipeline = useCallback(
    async (pipelineId: string) => {
      const result = await gitProvidersApi.cancelPipeline(
        params.repositoryId,
        pipelineId
      );
      await fetchPipelines();
      return result;
    },
    [params.repositoryId, fetchPipelines]
  );

  const retryPipeline = useCallback(
    async (pipelineId: string) => {
      const result = await gitProvidersApi.retryPipeline(
        params.repositoryId,
        pipelineId
      );
      await fetchPipelines();
      return result;
    },
    [params.repositoryId, fetchPipelines]
  );

  return {
    pipelines,
    pagination,
    stats,
    loading,
    error,
    refresh: fetchPipelines,
    triggerPipeline,
    cancelPipeline,
    retryPipeline,
  };
}

export function usePipeline(repositoryId: string, pipelineId: string | null) {
  const [pipeline, setPipeline] = useState<GitPipelineDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchPipeline = useCallback(async () => {
    if (!pipelineId) return;

    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getPipeline(repositoryId, pipelineId);
      setPipeline(data);
    } catch {
      setError(
        err instanceof Error ? err.message : 'Failed to fetch pipeline'
      );
    } finally {
      setLoading(false);
    }
  }, [repositoryId, pipelineId]);

  useEffect(() => {
    fetchPipeline();
  }, [fetchPipeline]);

  return {
    pipeline,
    loading,
    error,
    refresh: fetchPipeline,
  };
}

export function usePipelineJobs(
  repositoryId: string,
  pipelineId: string | null
) {
  const [jobs, setJobs] = useState<GitPipelineJob[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchJobs = useCallback(async () => {
    if (!pipelineId) return;

    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getPipelineJobs(
        repositoryId,
        pipelineId
      );
      setJobs(data);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch jobs');
    } finally {
      setLoading(false);
    }
  }, [repositoryId, pipelineId]);

  useEffect(() => {
    fetchJobs();
  }, [fetchJobs]);

  return {
    jobs,
    loading,
    error,
    refresh: fetchJobs,
  };
}

export function useJobLogs(
  repositoryId: string,
  pipelineId: string,
  jobId: string | null
) {
  const [logs, setLogs] = useState<string>('');
  const [isComplete, setIsComplete] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchLogs = useCallback(async () => {
    if (!jobId) return;

    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getJobLogs(
        repositoryId,
        pipelineId,
        jobId
      );
      setLogs(data.logs);
      setIsComplete(data.is_complete);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch logs');
    } finally {
      setLoading(false);
    }
  }, [repositoryId, pipelineId, jobId]);

  useEffect(() => {
    fetchLogs();
  }, [fetchLogs]);

  return {
    logs,
    isComplete,
    loading,
    error,
    refresh: fetchLogs,
  };
}
