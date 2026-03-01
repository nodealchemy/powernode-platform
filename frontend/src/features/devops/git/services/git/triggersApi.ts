import { apiClient } from '@/shared/services/apiClient';
import {
  GitWorkflowTrigger,
  GitWorkflowTriggerDetail,
  CreateGitWorkflowTriggerData,
  TestGitTriggerResult,
} from '../../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Git Workflow Triggers API
 * Manages AI workflow integration with Git events
 */
export const triggersApi = {
  /**
   * Get git triggers for a workflow trigger
   */
  getWorkflowGitTriggers: async (
    triggerId: string
  ): Promise<GitWorkflowTrigger[]> => {
    const response = await apiClient.get<ApiResponse<{
      git_triggers: GitWorkflowTrigger[];
      count: number;
    }>>(`/ai/triggers/${triggerId}/git_triggers`);
    return response.data.data?.git_triggers || [];
  },

  /**
   * Get all git triggers for a workflow
   */
  getWorkflowAllGitTriggers: async (
    workflowId: string
  ): Promise<GitWorkflowTrigger[]> => {
    const response = await apiClient.get<ApiResponse<{
      git_triggers: GitWorkflowTrigger[];
      count: number;
    }>>(`/ai/workflows/${workflowId}/git_triggers`);
    return response.data.data?.git_triggers || [];
  },

  /**
   * Get a specific git trigger
   */
  getGitTrigger: async (
    triggerId: string,
    gitTriggerId: string
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.get<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}`);
    return response.data.data.git_trigger;
  },

  /**
   * Create a git workflow trigger
   */
  createGitTrigger: async (
    triggerId: string,
    data: CreateGitWorkflowTriggerData
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.post<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers`, { git_trigger: data });
    return response.data.data.git_trigger;
  },

  /**
   * Update a git workflow trigger
   */
  updateGitTrigger: async (
    triggerId: string,
    gitTriggerId: string,
    data: Partial<CreateGitWorkflowTriggerData>
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.put<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}`, { git_trigger: data });
    return response.data.data.git_trigger;
  },

  /**
   * Delete a git workflow trigger
   */
  deleteGitTrigger: async (
    triggerId: string,
    gitTriggerId: string
  ): Promise<{ message: string }> => {
    const response = await apiClient.delete<ApiResponse<{
      message: string;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}`);
    return response.data.data;
  },

  /**
   * Test a git trigger with sample payload
   */
  testGitTrigger: async (
    triggerId: string,
    gitTriggerId: string,
    samplePayload: Record<string, unknown>
  ): Promise<TestGitTriggerResult> => {
    const response = await apiClient.post<ApiResponse<TestGitTriggerResult>>(
      `/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}/test`,
      { sample_payload: samplePayload }
    );
    return response.data.data;
  },

  /**
   * Activate a git trigger
   */
  activateGitTrigger: async (
    triggerId: string,
    gitTriggerId: string
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.post<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}/activate`);
    return response.data.data.git_trigger;
  },

  /**
   * Pause a git trigger
   */
  pauseGitTrigger: async (
    triggerId: string,
    gitTriggerId: string
  ): Promise<GitWorkflowTriggerDetail> => {
    const response = await apiClient.post<ApiResponse<{
      git_trigger: GitWorkflowTriggerDetail;
    }>>(`/ai/triggers/${triggerId}/git_triggers/${gitTriggerId}/pause`);
    return response.data.data.git_trigger;
  },
};
