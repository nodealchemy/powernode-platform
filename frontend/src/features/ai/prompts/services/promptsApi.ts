/**
 * AI Prompt Templates API Service
 */

import apiClient from '@/shared/services/api';
import type {
  PromptTemplate,
  PromptTemplateFormData,
  PromptTemplatesResponse,
  PromptPreviewResponse,
  PromptTemplatesParams,
} from '../types';

const BASE_PATH = '/ai/prompt_templates';

export const promptsApi = {
  /**
   * Get all prompt templates with optional filtering
   */
  getAll: async (params?: PromptTemplatesParams): Promise<PromptTemplatesResponse> => {
    const response = await apiClient.get<{ data: PromptTemplatesResponse }>(
      BASE_PATH,
      { params }
    );
    return response.data.data;
  },

  /**
   * Get a single prompt template by ID
   */
  getById: async (id: string, includeVersions = false): Promise<PromptTemplate> => {
    const response = await apiClient.get<{ data: { prompt_template: PromptTemplate } }>(
      `${BASE_PATH}/${id}`,
      { params: { include_versions: includeVersions } }
    );
    return response.data.data.prompt_template;
  },

  /**
   * Create a new prompt template
   */
  create: async (data: PromptTemplateFormData): Promise<PromptTemplate> => {
    const response = await apiClient.post<{ data: { prompt_template: PromptTemplate } }>(
      BASE_PATH,
      { prompt_template: data }
    );
    return response.data.data.prompt_template;
  },

  /**
   * Update an existing prompt template
   */
  update: async (id: string, data: Partial<PromptTemplateFormData>): Promise<PromptTemplate> => {
    const response = await apiClient.patch<{ data: { prompt_template: PromptTemplate } }>(
      `${BASE_PATH}/${id}`,
      { prompt_template: data }
    );
    return response.data.data.prompt_template;
  },

  /**
   * Delete a prompt template
   */
  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`${BASE_PATH}/${id}`);
  },

  /**
   * Preview a prompt template with provided variables
   */
  preview: async (id: string, variables: Record<string, string>): Promise<PromptPreviewResponse> => {
    const response = await apiClient.post<{ data: PromptPreviewResponse }>(
      `${BASE_PATH}/${id}/preview`,
      { variables }
    );
    return response.data.data;
  },

  /**
   * Duplicate a prompt template
   */
  duplicate: async (id: string): Promise<PromptTemplate> => {
    const response = await apiClient.post<{ data: { prompt_template: PromptTemplate } }>(
      `${BASE_PATH}/${id}/duplicate`
    );
    return response.data.data.prompt_template;
  },
};

export default promptsApi;
