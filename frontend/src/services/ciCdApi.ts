import { apiClient } from '@/shared/services/apiClient';
import type {
  CiCdProvider,
  CiCdProviderFormData,
  CiCdProvidersResponse,
  CiCdPromptTemplate,
  CiCdPromptTemplateFormData,
  CiCdPromptTemplatesResponse,
  CiCdPromptPreviewResponse,
  CiCdPipeline,
  CiCdPipelineFormData,
  CiCdPipelinesResponse,
  CiCdPipelineExportResponse,
  CiCdPipelineRun,
  CiCdPipelineRunsResponse,
  CiCdSchedule,
  CiCdScheduleFormData,
  CiCdSchedulesResponse,
  CiCdRepository,
  CiCdRepositoryFormData,
  CiCdRepositoriesResponse,
  CiCdConnectionTestResponse,
} from '@/types/cicd';

const BASE_PATH = '/ci_cd';

// ==================== Providers ====================

export const ciCdProvidersApi = {
  getAll: async (params?: { provider_type?: string; is_active?: boolean }) => {
    const response = await apiClient.get<{ data: CiCdProvidersResponse }>(
      `${BASE_PATH}/providers`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includeRepositories = false) => {
    const response = await apiClient.get<{ data: { provider: CiCdProvider } }>(
      `${BASE_PATH}/providers/${id}`,
      { params: { include_repositories: includeRepositories } }
    );
    return response.data.data.provider;
  },

  create: async (data: CiCdProviderFormData) => {
    const response = await apiClient.post<{ data: { provider: CiCdProvider } }>(
      `${BASE_PATH}/providers`,
      { provider: data }
    );
    return response.data.data.provider;
  },

  update: async (id: string, data: Partial<CiCdProviderFormData>) => {
    const response = await apiClient.patch<{ data: { provider: CiCdProvider } }>(
      `${BASE_PATH}/providers/${id}`,
      { provider: data }
    );
    return response.data.data.provider;
  },

  delete: async (id: string) => {
    await apiClient.delete(`${BASE_PATH}/providers/${id}`);
  },

  testConnection: async (id: string) => {
    const response = await apiClient.post<{ data: CiCdConnectionTestResponse }>(
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

export const ciCdPromptTemplatesApi = {
  getAll: async (params?: { category?: string; is_active?: boolean; root_only?: boolean }) => {
    const response = await apiClient.get<{ data: CiCdPromptTemplatesResponse }>(
      `${BASE_PATH}/prompt_templates`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includeVersions = false) => {
    const response = await apiClient.get<{ data: { prompt_template: CiCdPromptTemplate } }>(
      `${BASE_PATH}/prompt_templates/${id}`,
      { params: { include_versions: includeVersions } }
    );
    return response.data.data.prompt_template;
  },

  create: async (data: CiCdPromptTemplateFormData) => {
    const response = await apiClient.post<{ data: { prompt_template: CiCdPromptTemplate } }>(
      `${BASE_PATH}/prompt_templates`,
      { prompt_template: data }
    );
    return response.data.data.prompt_template;
  },

  update: async (id: string, data: Partial<CiCdPromptTemplateFormData>) => {
    const response = await apiClient.patch<{ data: { prompt_template: CiCdPromptTemplate } }>(
      `${BASE_PATH}/prompt_templates/${id}`,
      { prompt_template: data }
    );
    return response.data.data.prompt_template;
  },

  delete: async (id: string) => {
    await apiClient.delete(`${BASE_PATH}/prompt_templates/${id}`);
  },

  preview: async (id: string, variables: Record<string, string>) => {
    const response = await apiClient.post<{ data: CiCdPromptPreviewResponse }>(
      `${BASE_PATH}/prompt_templates/${id}/preview`,
      { variables }
    );
    return response.data.data;
  },

  duplicate: async (id: string) => {
    const response = await apiClient.post<{ data: { prompt_template: CiCdPromptTemplate } }>(
      `${BASE_PATH}/prompt_templates/${id}/duplicate`
    );
    return response.data.data.prompt_template;
  },
};

// ==================== Pipelines ====================

export const ciCdPipelinesApi = {
  getAll: async (params?: { is_active?: boolean }) => {
    const response = await apiClient.get<{ data: CiCdPipelinesResponse }>(
      `${BASE_PATH}/pipelines`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includeRuns = false) => {
    const response = await apiClient.get<{ data: { pipeline: CiCdPipeline } }>(
      `${BASE_PATH}/pipelines/${id}`,
      { params: { include_runs: includeRuns } }
    );
    return response.data.data.pipeline;
  },

  create: async (data: CiCdPipelineFormData) => {
    const response = await apiClient.post<{ data: { pipeline: CiCdPipeline } }>(
      `${BASE_PATH}/pipelines`,
      { pipeline: data, steps: data.steps }
    );
    return response.data.data.pipeline;
  },

  update: async (id: string, data: Partial<CiCdPipelineFormData>) => {
    const response = await apiClient.patch<{ data: { pipeline: CiCdPipeline } }>(
      `${BASE_PATH}/pipelines/${id}`,
      { pipeline: data, steps: data.steps }
    );
    return response.data.data.pipeline;
  },

  delete: async (id: string) => {
    await apiClient.delete(`${BASE_PATH}/pipelines/${id}`);
  },

  trigger: async (id: string, context?: Record<string, unknown>) => {
    const response = await apiClient.post<{ data: { pipeline_run: CiCdPipelineRun } }>(
      `${BASE_PATH}/pipelines/${id}/trigger`,
      { context }
    );
    return response.data.data.pipeline_run;
  },

  exportYaml: async (id: string) => {
    const response = await apiClient.get<{ data: CiCdPipelineExportResponse }>(
      `${BASE_PATH}/pipelines/${id}/export_yaml`
    );
    return response.data.data;
  },

  duplicate: async (id: string) => {
    const response = await apiClient.post<{ data: { pipeline: CiCdPipeline } }>(
      `${BASE_PATH}/pipelines/${id}/duplicate`
    );
    return response.data.data.pipeline;
  },
};

// ==================== Pipeline Runs ====================

export const ciCdPipelineRunsApi = {
  getAll: async (params?: {
    pipeline_id?: string;
    status?: string;
    trigger_type?: string;
    page?: number;
    per_page?: number;
  }) => {
    const response = await apiClient.get<{ data: CiCdPipelineRunsResponse }>(
      `${BASE_PATH}/pipeline_runs`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string) => {
    const response = await apiClient.get<{ data: { pipeline_run: CiCdPipelineRun } }>(
      `${BASE_PATH}/pipeline_runs/${id}`
    );
    return response.data.data.pipeline_run;
  },

  cancel: async (id: string) => {
    const response = await apiClient.post<{ data: { pipeline_run: CiCdPipelineRun } }>(
      `${BASE_PATH}/pipeline_runs/${id}/cancel`
    );
    return response.data.data.pipeline_run;
  },

  retry: async (id: string) => {
    const response = await apiClient.post<{ data: { pipeline_run: CiCdPipelineRun } }>(
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

export const ciCdSchedulesApi = {
  getAll: async (params?: { pipeline_id?: string; is_active?: boolean }) => {
    const response = await apiClient.get<{ data: CiCdSchedulesResponse }>(
      `${BASE_PATH}/schedules`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includePipeline = false) => {
    const response = await apiClient.get<{ data: { schedule: CiCdSchedule } }>(
      `${BASE_PATH}/schedules/${id}`,
      { params: { include_pipeline: includePipeline } }
    );
    return response.data.data.schedule;
  },

  create: async (data: CiCdScheduleFormData) => {
    const response = await apiClient.post<{ data: { schedule: CiCdSchedule } }>(
      `${BASE_PATH}/schedules`,
      { schedule: data }
    );
    return response.data.data.schedule;
  },

  update: async (id: string, data: Partial<CiCdScheduleFormData>) => {
    const response = await apiClient.patch<{ data: { schedule: CiCdSchedule } }>(
      `${BASE_PATH}/schedules/${id}`,
      { schedule: data }
    );
    return response.data.data.schedule;
  },

  delete: async (id: string) => {
    await apiClient.delete(`${BASE_PATH}/schedules/${id}`);
  },

  toggle: async (id: string) => {
    const response = await apiClient.post<{ data: { schedule: CiCdSchedule } }>(
      `${BASE_PATH}/schedules/${id}/toggle`
    );
    return response.data.data.schedule;
  },
};

// ==================== Repositories ====================

export const ciCdRepositoriesApi = {
  getAll: async (params?: { provider_id?: string; is_active?: boolean }) => {
    const response = await apiClient.get<{ data: CiCdRepositoriesResponse }>(
      `${BASE_PATH}/repositories`,
      { params }
    );
    return response.data.data;
  },

  getById: async (id: string, includePipelines = false) => {
    const response = await apiClient.get<{ data: { repository: CiCdRepository } }>(
      `${BASE_PATH}/repositories/${id}`,
      { params: { include_pipelines: includePipelines } }
    );
    return response.data.data.repository;
  },

  create: async (data: CiCdRepositoryFormData) => {
    const response = await apiClient.post<{ data: { repository: CiCdRepository } }>(
      `${BASE_PATH}/repositories`,
      { repository: data }
    );
    return response.data.data.repository;
  },

  update: async (id: string, data: Partial<CiCdRepositoryFormData>) => {
    const response = await apiClient.patch<{ data: { repository: CiCdRepository } }>(
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
    const response = await apiClient.post<{ data: { repository: CiCdRepository } }>(
      `${BASE_PATH}/repositories/${id}/attach_pipeline`,
      { pipeline_id: pipelineId, overrides }
    );
    return response.data.data.repository;
  },

  detachPipeline: async (id: string, pipelineId: string) => {
    const response = await apiClient.delete<{ data: { repository: CiCdRepository } }>(
      `${BASE_PATH}/repositories/${id}/detach_pipeline`,
      { params: { pipeline_id: pipelineId } }
    );
    return response.data.data.repository;
  },
};

// Combined API export for convenience
// Note: AI configuration is now managed through the global AiProvider system
// Use providersApi from '@/shared/services/ai/ProvidersApiService' for AI provider management
export const ciCdApi = {
  providers: ciCdProvidersApi,
  promptTemplates: ciCdPromptTemplatesApi,
  pipelines: ciCdPipelinesApi,
  pipelineRuns: ciCdPipelineRunsApi,
  schedules: ciCdSchedulesApi,
  repositories: ciCdRepositoriesApi,
};

export default ciCdApi;
