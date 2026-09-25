import { apiClient } from '@/shared/services/apiClient';
import type {
  DevopsPipeline,
  DevopsPipelineFormData,
  DevopsPipelinesResponse,
  DevopsPipelineExportResponse,
  DevopsPipelineRun,
  DevopsPipelineRunsResponse,
} from '@/types/devops-pipelines';

// DevOps Pipelines API Service
// Uses /api/v1/devops namespace for all pipeline-related endpoints
const BASE_PATH = '/devops';

// ==================== Pipelines ====================

export const devopsPipelinesApi = {
  getAll: async (params?: { is_active?: boolean }) => {
    const response = await apiClient.get<{ data: DevopsPipelinesResponse }>(
      `${BASE_PATH}/pipelines`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includeRuns = false) => {
    const response = await apiClient.get<{ data: { pipeline: DevopsPipeline } }>(
      `${BASE_PATH}/pipelines/${id}`,
      { params: { include_runs: includeRuns } }
    );
    return response.data.data.pipeline;
  },

  create: async (data: DevopsPipelineFormData) => {
    const response = await apiClient.post<{ data: { pipeline: DevopsPipeline } }>(
      `${BASE_PATH}/pipelines`,
      { pipeline: data, steps: data.steps }
    );
    return response.data.data.pipeline;
  },

  update: async (id: string, data: Partial<DevopsPipelineFormData>) => {
    const response = await apiClient.patch<{ data: { pipeline: DevopsPipeline } }>(
      `${BASE_PATH}/pipelines/${id}`,
      { pipeline: data, steps: data.steps }
    );
    return response.data.data.pipeline;
  },

  delete: async (id: string) => {
    await apiClient.delete(`${BASE_PATH}/pipelines/${id}`);
  },

  trigger: async (id: string, context?: Record<string, unknown>) => {
    const response = await apiClient.post<{ data: { pipeline_run: DevopsPipelineRun } }>(
      `${BASE_PATH}/pipelines/${id}/trigger`,
      { context }
    );
    return response.data.data.pipeline_run;
  },

  exportYaml: async (id: string) => {
    const response = await apiClient.get<{ data: DevopsPipelineExportResponse }>(
      `${BASE_PATH}/pipelines/${id}/export_yaml`
    );
    return response.data.data;
  },

  duplicate: async (id: string) => {
    const response = await apiClient.post<{ data: { pipeline: DevopsPipeline } }>(
      `${BASE_PATH}/pipelines/${id}/duplicate`
    );
    return response.data.data.pipeline;
  },
};

// ==================== Pipeline Runs ====================

export const devopsPipelineRunsApi = {
  getAll: async (params?: {
    pipeline_id?: string;
    status?: string;
    trigger_type?: string;
    page?: number;
    per_page?: number;
  }) => {
    const response = await apiClient.get<{ data: DevopsPipelineRunsResponse }>(
      `${BASE_PATH}/pipeline_runs`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string) => {
    const response = await apiClient.get<{ data: { pipeline_run: DevopsPipelineRun } }>(
      `${BASE_PATH}/pipeline_runs/${id}`
    );
    return response.data.data.pipeline_run;
  },

  cancel: async (id: string) => {
    const response = await apiClient.post<{ data: { pipeline_run: DevopsPipelineRun } }>(
      `${BASE_PATH}/pipeline_runs/${id}/cancel`
    );
    return response.data.data.pipeline_run;
  },

  retry: async (id: string) => {
    const response = await apiClient.post<{ data: { pipeline_run: DevopsPipelineRun } }>(
      `${BASE_PATH}/pipeline_runs/${id}/retry`
    );
    return response.data.data.pipeline_run;
  },

  getLogs: async (id: string) => {
    const response = await apiClient.get<{
      data: {
        pipeline_run_id: string;
        status: string;
        logs: Array<{
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
        }>;
      };
    }>(`${BASE_PATH}/pipeline_runs/${id}/logs`);
    return response.data.data;
  },
};

// Combined API export for convenience
// Note: AI configuration is now managed through the global AiProvider system
// Use providersApi from '@/shared/services/ai/ProvidersApiService' for AI provider management
export const devopsApi = {
  pipelines: devopsPipelinesApi,
  pipelineRuns: devopsPipelineRunsApi,
};

export default devopsApi;
