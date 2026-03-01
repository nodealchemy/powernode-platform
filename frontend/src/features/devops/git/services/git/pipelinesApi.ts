import { apiClient } from '@/shared/services/apiClient';
import {
  GitPipeline,
  GitPipelineDetail,
  GitPipelineJob,
  GitPipelineJobDetail,
  PaginationInfo,
  PipelineStats,
} from '../../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Git Pipelines API
 * Manages CI/CD pipelines and jobs
 */
export const pipelinesApi = {
  /**
   * Get pipelines for a repository
   */
  getPipelines: async (
    repositoryId: string,
    params?: {
      page?: number;
      per_page?: number;
      status?: string;
      conclusion?: string;
      ref?: string;
    }
  ): Promise<{
    pipelines: GitPipeline[];
    pagination: PaginationInfo;
    stats: PipelineStats;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      pipelines: GitPipeline[];
      pagination: PaginationInfo;
      stats: PipelineStats;
    }>>(`/git/repositories/${repositoryId}/pipelines`, { params });
    return response.data.data;
  },

  /**
   * Get a specific pipeline
   */
  getPipeline: async (
    repositoryId: string,
    pipelineId: string
  ): Promise<GitPipelineDetail> => {
    const response = await apiClient.get<ApiResponse<{
      pipeline: GitPipelineDetail;
    }>>(`/git/repositories/${repositoryId}/pipelines/${pipelineId}`);
    return response.data.data.pipeline;
  },

  /**
   * Trigger a pipeline
   */
  triggerPipeline: async (
    repositoryId: string,
    options?: {
      ref?: string;
      workflow_id?: string;
      inputs?: Record<string, string>;
    }
  ): Promise<{ message: string; pipeline_id?: string }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      pipeline_id?: string;
    }>>(`/git/repositories/${repositoryId}/pipelines/trigger`, options);
    return response.data.data;
  },

  /**
   * Cancel a pipeline
   */
  cancelPipeline: async (
    repositoryId: string,
    pipelineId: string
  ): Promise<{ message: string }> => {
    const response = await apiClient.post<ApiResponse<{ message: string }>>(
      `/git/repositories/${repositoryId}/pipelines/${pipelineId}/cancel`
    );
    return response.data.data;
  },

  /**
   * Retry a pipeline
   */
  retryPipeline: async (
    repositoryId: string,
    pipelineId: string
  ): Promise<{ message: string; new_pipeline_id?: string }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      new_pipeline_id?: string;
    }>>(`/git/repositories/${repositoryId}/pipelines/${pipelineId}/retry`);
    return response.data.data;
  },

  /**
   * Get jobs for a pipeline
   */
  getPipelineJobs: async (
    repositoryId: string,
    pipelineId: string
  ): Promise<GitPipelineJob[]> => {
    const response = await apiClient.get<ApiResponse<{
      jobs: GitPipelineJob[];
      count: number;
    }>>(`/git/repositories/${repositoryId}/pipelines/${pipelineId}/jobs`);
    return response.data.data?.jobs || [];
  },

  /**
   * Get a specific job
   */
  getJob: async (
    repositoryId: string,
    pipelineId: string,
    jobId: string
  ): Promise<GitPipelineJobDetail> => {
    const response = await apiClient.get<ApiResponse<{
      job: GitPipelineJobDetail;
    }>>(
      `/git/repositories/${repositoryId}/pipelines/${pipelineId}/jobs/${jobId}`
    );
    return response.data.data.job;
  },

  /**
   * Get job logs
   */
  getJobLogs: async (
    repositoryId: string,
    pipelineId: string,
    jobId: string
  ): Promise<{ job_id: string; logs: string; is_complete: boolean }> => {
    const response = await apiClient.get<ApiResponse<{
      job_id: string;
      logs: string;
      is_complete: boolean;
    }>>(
      `/git/repositories/${repositoryId}/pipelines/${pipelineId}/jobs/${jobId}/logs`
    );
    return response.data.data;
  },
};
