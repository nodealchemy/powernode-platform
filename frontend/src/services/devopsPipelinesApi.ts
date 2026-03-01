import { apiClient } from '@/shared/services/apiClient';
import type {
  DevopsProvider,
  DevopsProviderFormData,
  DevopsProvidersResponse,
  DevopsPromptTemplate,
  DevopsPromptTemplateFormData,
  DevopsPromptTemplatesResponse,
  DevopsPromptPreviewResponse,
  DevopsPipeline,
  DevopsPipelineFormData,
  DevopsPipelinesResponse,
  DevopsPipelineExportResponse,
  DevopsPipelineRun,
  DevopsPipelineRunsResponse,
  DevopsSchedule,
  DevopsScheduleFormData,
  DevopsSchedulesResponse,
  DevopsRepository,
  DevopsRepositoryFormData,
  DevopsRepositoriesResponse,
  DevopsConnectionTestResponse,
} from '@/types/devops-pipelines';

// DevOps Pipelines API Service
// Uses /api/v1/devops namespace for all pipeline-related endpoints
const BASE_PATH = '/devops';

// ==================== Providers ====================

export const devopsProvidersApi = {
  getAll: async (params?: { provider_type?: string; is_active?: boolean }) => {
    const response = await apiClient.get<{ data: DevopsProvidersResponse }>(
      `${BASE_PATH}/providers`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includeRepositories = false) => {
    const response = await apiClient.get<{ data: { provider: DevopsProvider } }>(
      `${BASE_PATH}/providers/${id}`,
      { params: { include_repositories: includeRepositories } }
    );
    return response.data.data.provider;
  },

  create: async (data: DevopsProviderFormData) => {
    const response = await apiClient.post<{ data: { provider: DevopsProvider } }>(
      `${BASE_PATH}/providers`,
      { provider: data }
    );
    return response.data.data.provider;
  },

  update: async (id: string, data: Partial<DevopsProviderFormData>) => {
    const response = await apiClient.patch<{ data: { provider: DevopsProvider } }>(
      `${BASE_PATH}/providers/${id}`,
      { provider: data }
    );
    return response.data.data.provider;
  },

  delete: async (id: string) => {
    await apiClient.delete(`${BASE_PATH}/providers/${id}`);
  },

  testConnection: async (id: string) => {
    const response = await apiClient.post<{ data: DevopsConnectionTestResponse }>(
      `${BASE_PATH}/providers/${id}/test_connection`
    );
    return response.data.data;
  },

  syncRepositories: async (id: string) => {
    const response = await apiClient.post<{ data: { message: string } }>(
      `${BASE_PATH}/providers/${id}/sync_repositories`
    );
    return response.data.data;
  },
};

// ==================== Prompt Templates ====================

export const devopsPromptTemplatesApi = {
  getAll: async (params?: { category?: string; is_active?: boolean; root_only?: boolean }) => {
    const response = await apiClient.get<{ data: DevopsPromptTemplatesResponse }>(
      `${BASE_PATH}/prompt_templates`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includeVersions = false) => {
    const response = await apiClient.get<{ data: { prompt_template: DevopsPromptTemplate } }>(
      `${BASE_PATH}/prompt_templates/${id}`,
      { params: { include_versions: includeVersions } }
    );
    return response.data.data.prompt_template;
  },

  create: async (data: DevopsPromptTemplateFormData) => {
    const response = await apiClient.post<{ data: { prompt_template: DevopsPromptTemplate } }>(
      `${BASE_PATH}/prompt_templates`,
      { prompt_template: data }
    );
    return response.data.data.prompt_template;
  },

  update: async (id: string, data: Partial<DevopsPromptTemplateFormData>) => {
    const response = await apiClient.patch<{ data: { prompt_template: DevopsPromptTemplate } }>(
      `${BASE_PATH}/prompt_templates/${id}`,
      { prompt_template: data }
    );
    return response.data.data.prompt_template;
  },

  delete: async (id: string) => {
    await apiClient.delete(`${BASE_PATH}/prompt_templates/${id}`);
  },

  preview: async (id: string, variables: Record<string, string>) => {
    const response = await apiClient.post<{ data: DevopsPromptPreviewResponse }>(
      `${BASE_PATH}/prompt_templates/${id}/preview`,
      { variables }
    );
    return response.data.data;
  },

  duplicate: async (id: string) => {
    const response = await apiClient.post<{ data: { prompt_template: DevopsPromptTemplate } }>(
      `${BASE_PATH}/prompt_templates/${id}/duplicate`
    );
    return response.data.data.prompt_template;
  },
};

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

// ==================== Schedules ====================

export const devopsSchedulesApi = {
  getAll: async (params?: { pipeline_id?: string; is_active?: boolean }) => {
    const response = await apiClient.get<{ data: DevopsSchedulesResponse }>(
      `${BASE_PATH}/schedules`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includePipeline = false) => {
    const response = await apiClient.get<{ data: { schedule: DevopsSchedule } }>(
      `${BASE_PATH}/schedules/${id}`,
      { params: { include_pipeline: includePipeline } }
    );
    return response.data.data.schedule;
  },

  create: async (data: DevopsScheduleFormData) => {
    const response = await apiClient.post<{ data: { schedule: DevopsSchedule } }>(
      `${BASE_PATH}/schedules`,
      { schedule: data }
    );
    return response.data.data.schedule;
  },

  update: async (id: string, data: Partial<DevopsScheduleFormData>) => {
    const response = await apiClient.patch<{ data: { schedule: DevopsSchedule } }>(
      `${BASE_PATH}/schedules/${id}`,
      { schedule: data }
    );
    return response.data.data.schedule;
  },

  delete: async (id: string) => {
    await apiClient.delete(`${BASE_PATH}/schedules/${id}`);
  },

  toggle: async (id: string) => {
    const response = await apiClient.post<{ data: { schedule: DevopsSchedule } }>(
      `${BASE_PATH}/schedules/${id}/toggle`
    );
    return response.data.data.schedule;
  },
};

// ==================== Repositories ====================

export const devopsRepositoriesApi = {
  getAll: async (params?: { provider_id?: string; is_active?: boolean }) => {
    const response = await apiClient.get<{ data: DevopsRepositoriesResponse }>(
      `${BASE_PATH}/repositories`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includePipelines = false) => {
    const response = await apiClient.get<{ data: { repository: DevopsRepository } }>(
      `${BASE_PATH}/repositories/${id}`,
      { params: { include_pipelines: includePipelines } }
    );
    return response.data.data.repository;
  },

  create: async (data: DevopsRepositoryFormData) => {
    const response = await apiClient.post<{ data: { repository: DevopsRepository } }>(
      `${BASE_PATH}/repositories`,
      { repository: data }
    );
    return response.data.data.repository;
  },

  update: async (id: string, data: Partial<DevopsRepositoryFormData>) => {
    const response = await apiClient.patch<{ data: { repository: DevopsRepository } }>(
      `${BASE_PATH}/repositories/${id}`,
      { repository: data }
    );
    return response.data.data.repository;
  },

  delete: async (id: string) => {
    await apiClient.delete(`${BASE_PATH}/repositories/${id}`);
  },

  sync: async (id: string) => {
    const response = await apiClient.post<{ data: { message: string } }>(
      `${BASE_PATH}/repositories/${id}/sync`
    );
    return response.data.data;
  },

  attachPipeline: async (
    id: string,
    pipelineId: string,
    overrides?: Record<string, unknown>
  ) => {
    const response = await apiClient.post<{ data: { repository: DevopsRepository } }>(
      `${BASE_PATH}/repositories/${id}/attach_pipeline`,
      { pipeline_id: pipelineId, overrides }
    );
    return response.data.data.repository;
  },

  detachPipeline: async (id: string, pipelineId: string) => {
    const response = await apiClient.delete<{ data: { repository: DevopsRepository } }>(
      `${BASE_PATH}/repositories/${id}/detach_pipeline`,
      { params: { pipeline_id: pipelineId } }
    );
    return response.data.data.repository;
  },
};

// Combined API export for convenience
// Note: AI configuration is now managed through the global AiProvider system
// Use providersApi from '@/shared/services/ai/ProvidersApiService' for AI provider management
export const devopsApi = {
  providers: devopsProvidersApi,
  promptTemplates: devopsPromptTemplatesApi,
  pipelines: devopsPipelinesApi,
  pipelineRuns: devopsPipelineRunsApi,
  schedules: devopsSchedulesApi,
  repositories: devopsRepositoriesApi,
};

export default devopsApi;
